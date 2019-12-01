#######################################################################
# CoverageTools.jl
# Take Julia test coverage results and bundle them up in JSONs
# https://github.com/JuliaCI/CoverageTools.jl
#######################################################################

using CoverageTools, Test, LibGit2

if VERSION < v"1.1"
isnothing(x) = false
isnothing(x::Nothing) = true
end

@testset "CoverageTools" begin
withenv("DISABLE_AMEND_COVERAGE_FROM_SRC" => nothing) do

@testset "iscovfile" begin
    # test our filename matching. These aren't exported functions but it's probably
    # a good idea to have explicit tests for them, as they're used to match files
    # that get deleted
    @test CoverageTools.iscovfile("test.jl.cov")
    @test CoverageTools.iscovfile("test.jl.2934.cov")
    @test CoverageTools.iscovfile("/home/somebody/test.jl.2934.cov")
    @test !CoverageTools.iscovfile("test.ji.2934.cov")
    @test !CoverageTools.iscovfile("test.jl.2934.cove")
    @test !CoverageTools.iscovfile("test.jicov")
    @test !CoverageTools.iscovfile("test.c.cov")
    @test CoverageTools.iscovfile("test.jl.cov", "test.jl")
    @test !CoverageTools.iscovfile("test.jl.cov", "other.jl")
    @test CoverageTools.iscovfile("test.jl.8392.cov", "test.jl")
    @test CoverageTools.iscovfile("/somedir/test.jl.8392.cov", "/somedir/test.jl")
    @test !CoverageTools.iscovfile("/otherdir/test.jl.cov", "/somedir/test.jl")
end

@testset "isfuncexpr" begin
    @test CoverageTools.isfuncexpr(:(f() = x))
    @test CoverageTools.isfuncexpr(:(function() end))
    @test CoverageTools.isfuncexpr(:(function g() end))
    @test CoverageTools.isfuncexpr(:(function g() where {T} end))
    @test !CoverageTools.isfuncexpr("2")
    @test !CoverageTools.isfuncexpr(:(f = x))
    @test CoverageTools.isfuncexpr(:(() -> x))
    @test CoverageTools.isfuncexpr(:(x -> x))
    @test CoverageTools.isfuncexpr(:(f() where A = x))
    @test CoverageTools.isfuncexpr(:(f() where A where B = x))
end

@testset "Processing coverage" begin
    cd(dirname(@__DIR__)) do
        datadir = joinpath("test", "data")
        # Process a saved set of coverage data...
        r = process_file(joinpath(datadir, "CoverageTools.jl"))

        # ... and memory data
        malloc_results = analyze_malloc(datadir)
        filename = joinpath(datadir, "testparser.jl.9172.mem")
        @test malloc_results == [CoverageTools.MallocInfo(96669, filename, 2)]

        lcov = IOBuffer()
        # we only have a single file, but we want to test on the Vector of file results
        LCOV.write(lcov, FileCoverage[r])
        expected = read(joinpath(datadir, "tracefiles", "expected.info"), String)
        if Sys.iswindows()
            expected = replace(expected, "\r\n" => "\n")
            expected = replace(expected, "SF:test/data/CoverageTools.jl\n" => "SF:test\\data\\CoverageTools.jl\n")
        end
        @test String(take!(lcov)) == expected

        # LCOV.writefile is a short-hand for writing to a file
        lcov = joinpath(datadir, "lcov_output_temp.info")
        LCOV.writefile(lcov, FileCoverage[r])
        expected = read(joinpath(datadir, "tracefiles", "expected.info"), String)
        if Sys.iswindows()
            expected = replace(expected, "\r\n" => "\n")
            expected = replace(expected, "SF:test/data/CoverageTools.jl\n" => "SF:test\\data\\CoverageTools.jl\n")
        end
        @test String(read(lcov)) == expected
        # tear down test file
        rm(lcov)

        # test that reading the LCOV file gives the same data
        lcov = LCOV.readfolder(datadir)
        @test length(lcov) == 1
        r2 = lcov[1]
        r2_filename = r2.filename
        if Sys.iswindows()
            r2_filename = replace(r2_filename, '/' => '\\')
        end
        @test r2_filename == r.filename
        @test r2.source == ""
        @test r2.coverage == r.coverage[1:length(r2.coverage)]
        @test all(isnothing, r.coverage[(length(r2.coverage) + 1):end])
        lcov2 = [FileCoverage(r2.filename, "sourcecode", CoverageTools.CovCount[nothing, 1, 0, nothing, 3]),
                 FileCoverage("file2.jl", "moresource2", CoverageTools.CovCount[1, nothing, 0, nothing, 2]),]
        lcov = merge_coverage_counts(lcov, lcov2, lcov)
        @test length(lcov) == 2
        r3 = lcov[1]
        @test r3.filename == r2.filename
        @test r3.source == "sourcecode"
        r3cov = CoverageTools.CovCount[x === nothing ? nothing : x * 2 for x in r2.coverage]
        r3cov[2] += 1
        r3cov[3] = 0
        r3cov[5] = 3
        @test r3.coverage == r3cov
        r4 = lcov[2]
        @test r4.filename == "file2.jl"
        @test r4.source == "moresource2"
        @test r4.coverage == lcov2[2].coverage

        # Test a file from scratch
        srcname = joinpath("test", "data", "testparser.jl")
        covname = srcname*".cov"
        # clean out any previous coverage files. Don't use clean_folder because we
        # need to preserve the pre-baked coverage file CoverageTools.jl.cov
        clean_file(srcname)
        cmdstr = "include($(repr(srcname))); using Test; @test f2(2) == 4"
        run(`$(Base.julia_cmd()) --startup-file=no --code-coverage=user -e $cmdstr`)
        r = process_file(srcname, datadir)

        target = CoverageTools.CovCount[nothing, 2, nothing, 0, nothing, 0, nothing, nothing, nothing, nothing, 0, nothing, nothing, nothing, nothing, nothing, 0, nothing, nothing, 0, nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing]
        target_disabled = map(x -> (x !== nothing && x > 0) ? x : nothing, target)
        @test r.coverage == target

        covtarget = (sum(x->x !== nothing && x > 0, target), sum(x->x !== nothing, target))
        @test get_summary(r) == covtarget
        @test get_summary(process_folder(datadir)) == (98, 106)

        r_disabled = withenv("DISABLE_AMEND_COVERAGE_FROM_SRC" => "yes") do
            process_file(srcname, datadir)
        end

        @test r_disabled.coverage == target_disabled
        amend_coverage_from_src!(r_disabled.coverage, r_disabled.filename)
        @test r_disabled.coverage == target

        # Handle an empty coverage vector
        emptycov = FileCoverage("", "", [])
        @test get_summary(emptycov) == (0, 0)

        @test isempty(CoverageTools.process_cov(joinpath("test", "fakefile"), datadir))

        # test clean_folder
        # set up the test folder
        datadir_temp = joinpath("test", "data_temp")
        cp(datadir, datadir_temp)
        # run clean_folder
        clean_folder(datadir_temp)
        # .cov files should be deleted
        @test !isfile(joinpath(datadir_temp, "CoverageTools.jl.cov"))
        # other files should remain untouched
        @test isfile(joinpath(datadir_temp, "CoverageTools.jl"))
        # tear down test data
        rm(datadir_temp; recursive=true)
    end
end

end # of withenv("DISABLE_AMEND_COVERAGE_FROM_SRC" => nothing)

end # of @testset "CoverageTools"
