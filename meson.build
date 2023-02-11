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

bc_link_args = []
if meson.get_compiler('d').get_id() == 'llvm'
    bc_link_args += '-link-defaultlib-shared=false'
endif

test_exe = executable(
    'expected-test',
    ['source/expected.d', 'tests/expected.d'],
    include_directories: include_directories('source'),
    d_args: ['-betterC', '-unittest'],
    link_args: bc_link_args
)
test('bctest', test_exe)
