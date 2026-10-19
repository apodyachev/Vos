module main

import os

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
