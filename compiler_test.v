module main

import os
import crypto.sha256

fn test_javascript_source_is_used_directly() {
	source := prepare_source('examples/hello.js') or { panic(err) }
	assert source.temp_dir == ''
	assert source.path == os.abs_path('examples/hello.js')
}

fn test_typescript_source_is_transpiled() {
	source := prepare_source('examples/hello.ts') or { panic(err) }
	defer {
		os.rmdir_all(source.temp_dir) or { panic(err) }
	}

	assert source.temp_dir != ''
	assert source.path.ends_with('hello.js')
	compiled := os.read_file(source.path) or { panic(err) }
	assert compiled.contains('from "./greeting.js"')
	dependency := os.read_file(os.join_path(source.temp_dir, 'greeting.js')) or { panic(err) }
	assert dependency.contains('Hello from TypeScript running in QuickJS')
}

fn test_javascript_runs_in_quickjs() {
	run_script('examples/hello.js') or { panic(err) }
}

fn test_typescript_runs_in_quickjs() {
	run_script('examples/hello.ts') or { panic(err) }
}

fn test_typescript_errors_stop_compilation() {
	prepare_source('examples/type-error.ts') or {
		assert err.msg().contains('TypeScript compilation failed')
		return
	}
	assert false, 'invalid TypeScript unexpectedly compiled'
}

fn test_local_typescript_compiler_is_discovered_from_script_directory() {
	temp_dir := os.join_path(os.temp_dir(), 'vos_local_tsc_test_${os.getpid()}')
	compiler_path := os.join_path(temp_dir, 'node_modules', 'typescript', 'bin', 'tsc')
	script_dir := os.join_path(temp_dir, 'src')
	os.mkdir_all(os.dir(compiler_path)) or { panic(err) }
	os.mkdir_all(script_dir) or { panic(err) }
	os.write_file(compiler_path, '') or { panic(err) }
	script_path := os.join_path(script_dir, 'index.ts')
	os.write_file(script_path, '') or { panic(err) }
	defer {
		os.rmdir_all(temp_dir) or { panic(err) }
	}

	assert find_local_typescript_compiler(script_path) == compiler_path
}

fn test_module_specifier_resolves_relative_local_modules() {
	temp_dir := os.join_path(os.temp_dir(), 'vos_local_module_test_${os.getpid()}')
	script_path := os.join_path(temp_dir, 'src', 'index.js')
	os.mkdir_all(os.dir(script_path)) or { panic(err) }
	defer {
		os.rmdir_all(temp_dir) or { panic(err) }
	}

	resolved := resolve_module_specifier(script_path, './lib/greeting.js')
	assert resolved == os.join_path(temp_dir, 'src', 'lib', 'greeting.js')
}

fn test_module_specifier_resolves_project_packages_and_package_entry_points() {
	temp_dir := os.join_path(os.temp_dir(), 'vos_npm_module_test_${os.getpid()}')
	script_path := os.join_path(temp_dir, 'src', 'index.js')
	package_path := os.join_path(temp_dir, 'node_modules', '@example', 'greeting')
	os.mkdir_all(os.dir(script_path)) or { panic(err) }
	os.mkdir_all(os.join_path(package_path, 'dist')) or { panic(err) }
	os.write_file(os.join_path(package_path, 'package.json'),
		'{"module":"./dist/index.js","main":"./index.js"}') or { panic(err) }
	os.write_file(os.join_path(package_path, 'dist', 'index.js'), 'export const greeting = "hi";') or {
		panic(err)
	}
	defer {
		os.rmdir_all(temp_dir) or { panic(err) }
	}

	resolved := resolve_module_specifier(script_path, '@example/greeting')
	assert resolved == os.join_path(package_path, 'dist', 'index.js')
}

fn test_module_specifier_resolves_package_subpaths_and_rejects_traversal() {
	temp_dir := os.join_path(os.temp_dir(), 'vos_npm_subpath_test_${os.getpid()}')
	script_path := os.join_path(temp_dir, 'src', 'index.js')
	package_path := os.join_path(temp_dir, 'node_modules', 'sample')
	os.mkdir_all(os.dir(script_path)) or { panic(err) }
	os.mkdir_all(os.join_path(package_path, 'lib')) or { panic(err) }
	os.write_file(os.join_path(package_path, 'lib', 'helper.js'), 'export const value = 1;') or {
		panic(err)
	}
	defer {
		os.rmdir_all(temp_dir) or { panic(err) }
	}

	assert resolve_module_specifier(script_path, 'sample/lib/helper.js') == os.join_path(package_path,
		'lib', 'helper.js')
	assert resolve_module_specifier(script_path, 'sample/../../outside.js') == ''
}

fn test_module_specifier_resolves_sibling_transitive_packages() {
	temp_dir := os.join_path(os.temp_dir(), 'vos_transitive_module_test_${os.getpid()}')
	package_dir := os.join_path(temp_dir, 'node_modules', 'parent', 'lib')
	child_package := os.join_path(temp_dir, 'node_modules', 'child')
	os.mkdir_all(package_dir) or { panic(err) }
	os.mkdir_all(child_package) or { panic(err) }
	os.write_file(os.join_path(child_package, 'index.js'), 'export const value = 2;') or {
		panic(err)
	}
	defer {
		os.rmdir_all(temp_dir) or { panic(err) }
	}

	resolved := resolve_module_specifier(os.join_path(package_dir, 'index.js'), 'child')
	assert resolved == os.join_path(child_package, 'index.js')
}

fn test_npm_package_specifier_accepts_package_name() {
	assert parse_npm_package_specifier('npm:lodash') or { panic(err) } == 'lodash'
}

fn test_npm_package_specifier_accepts_scoped_package() {
	assert parse_npm_package_specifier('npm:@types/node') or { panic(err) } == '@types/node'
}

fn test_npm_package_specifier_rejects_other_sources() {
	parse_npm_package_specifier('github:user/package') or {
		assert err.msg().contains('Unsupported package source')
		return
	}
	assert false, 'unsupported package source was accepted'
}

fn test_npm_package_specifier_rejects_invalid_names() {
	for specifier in ['npm:../outside', 'npm:package name', 'npm:@scope/', 'npm:-option'] {
		parse_npm_package_specifier(specifier) or { continue }
		assert false, 'invalid package specifier was accepted: ${specifier}'
	}
}

fn test_npm_project_name_normalizes_case_and_spaces() {
	assert npm_project_name('My Project') or { panic(err) } == 'my-project'
}

fn test_npm_project_name_rejects_invalid_names() {
	npm_project_name('Bad/Name') or {
		assert err.msg().contains('cannot be used')
		return
	}
	assert false, 'invalid npm project name was accepted'
}

fn test_npm_packages_use_application_data_directory() {
	application_dir := npm_application_directory()
	assert os.dir(application_dir) == os.data_dir()
	assert os.file_name(application_dir) == 'vos'
	assert os.file_name(os.join_path(application_dir, 'node_modules')) == 'node_modules'
}

fn test_remote_module_url_accepts_http_and_https() {
	assert parse_remote_module_url('https://example.com/mod.ts') or { panic(err) }.host == 'example.com'
	assert parse_remote_module_url('http://example.com/mod.js') or { panic(err) }.scheme.to_lower() == 'http'
}

fn test_remote_module_url_rejects_invalid_schemes_and_hosts() {
	for url in ['file:///tmp/module.js', 'ftp://example.com/module.js', 'https://'] {
		parse_remote_module_url(url) or { continue }
		assert false, 'invalid module URL was accepted: ${url}'
	}
}

fn test_remote_module_url_rejects_embedded_credentials() {
	parse_remote_module_url('https://user:password@example.com/module.js') or {
		assert err.msg().contains('embedded credentials')
		return
	}
	assert false, 'module URL with embedded credentials was accepted'
}

fn test_remote_module_cache_path_is_stable_and_keeps_source_extension() {
	url := 'https://example.com/mod.ts?version=1'
	cache_path := remote_module_cache_path(url) or { panic(err) }
	assert cache_path == remote_module_cache_path(url) or { panic(err) }
	assert cache_path.ends_with('module.ts')
	assert os.file_name(os.dir(cache_path)) == sha256.sum(url.bytes()).hex()
}

fn test_remote_module_cache_path_uses_safe_default_extension() {
	cache_path := remote_module_cache_path('https://example.com/download') or { panic(err) }
	assert cache_path.ends_with('module.js')
}
