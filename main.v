module main

import os
import herudi.vjs
import herudi.vjs.web

$if windows && gcc {
	#flag -include @VMODROOT/mingw_compat.h
}

fn print_usage() {
	println('Usage:')
	println('  vos <script.js|script.ts>')
	println('  vos install <npm:<package-name>|http(s)://<module-url>>')
	println('  vos new [project-name]')
	println('')
	println('Runs JavaScript or TypeScript using the QuickJS engine, or serves an HTML page.')
}

fn print_error(message string) {
	eprintln('Error: ${message}')
}

fn run_script(file_path string) ! {
	if !os.exists(file_path) {
		return error('File not found: ${file_path}')
	}

	extension := os.file_ext(file_path).to_lower()
	if extension != '.js' && extension != '.ts' {
		return error('Unsupported file format "${extension}". Provide a .js or .ts file.')
	}

	source := prepare_source(file_path)!
	defer {
		if source.temp_dir != '' {
			os.rmdir_all(source.temp_dir) or {
				eprintln('Warning: failed to remove temporary directory ${source.temp_dir}: ${err}')
			}
		}
	}

	rt := vjs.new_runtime()
	defer {
		rt.free()
	}

	ctx := rt.new_context()
	defer {
		ctx.free()
	}
	configure_module_loader(rt)
	web.console_api(ctx)

	previous_dir := os.getwd()
	script_dir := os.dir(os.abs_path(file_path))
	os.chdir(script_dir) or {
		return error('Failed to change working directory to ${script_dir}: ${err}')
	}
	defer {
		os.chdir(previous_dir) or {
			eprintln('Warning: failed to restore working directory ${previous_dir}: ${err}')
		}
	}

	value := ctx.eval_file(source.path, vjs.type_module) or {
		return error('JavaScript execution failed: ${err.msg()}')
	}
	defer {
		value.free()
	}

	ctx.end()
}

fn main() {
	if os.args.len < 2 || os.args[1] in ['--help', '-h'] {
		print_usage()
		return
	}
	if os.args[1] == 'serve' {
		if os.args.len < 3 {
			print_usage()
			exit(1)
		}
		extra_args := if os.args.len > 3 { os.args[3..] } else { []string{} }
		address_arg := extra_args.filter(!it.starts_with('--'))
		address := if address_arg.len > 0 { address_arg[0] } else { '127.0.0.1:3000' }
		profile := '--profile' in extra_args
		serve_page(os.args[2], address, profile) or {
			eprintln('Error: ${err.msg()}')
			exit(1)
		}
		return
	}

	if os.args[1] == 'install' {
		if os.args.len != 3 {
			print_usage()
			exit(2)
		}
		install_package(os.args[2]) or {
			print_error(err.msg())
			exit(1)
		}
		return
	}

	if os.args[1] == 'new' {
		if os.args.len > 3 {
			print_usage()
			exit(2)
		}
		project_name := if os.args.len == 3 { os.args[2] } else { '' }
		create_typescript_project(project_name) or {
			print_error(err.msg())
			exit(1)
		}
		return
	}

	run_script(os.args[1]) or {
		print_error(err.msg())
		exit(1)
	}
}
