import CoverageCore
coveragecore_cov_res = CoverageCore.process_folder()

using Pkg
Pkg.add("Coverage")
import Coverage
coverage_cov_res = Coverage.process_folder()
Coverage.Coveralls.submit(coverage_cov_res)
Coverage.Codecov.submit(coverage_cov_res)
