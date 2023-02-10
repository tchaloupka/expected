project('expected', 'd',
    version: '0.3.4'
)

expected_build_versions = []

expected_lib = static_library(
    'expected',
    'source/expected.d',
    d_module_versions: expected_build_versions
)

expected_dep = declare_dependency(
    include_directories: include_directories('source'),
    link_with: expected_lib
)

test_exe = executable(
    'expected-test',
    ['source/expected.d', 'tests/expected.d'],
    include_directories: include_directories('source'),
    d_args: ['-betterC', '-unittest'],
    link_args: ['-link-defaultlib-shared=false']
)
test('bctest', test_exe)
