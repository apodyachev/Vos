module main

import os
import time

struct PreparedSource {
	path     string
	temp_dir string
}

fn prepare_source(file_path string) !PreparedSource {
	if os.file_ext(file_path).to_lower() != '.ts' {
		return PreparedSource{
			path: os.abs_path(file_path)
		}
	}

	temp_dir := os.join_path(os.temp_dir(), 'vos_${os.getpid()}_${time.now().unix_nano()}')
	os.mkdir_all(temp_dir)!

	command := '${os.quoted_path('tsc')} --target ES2022 --module ESNext --moduleResolution Bundler --skipLibCheck --outDir ${os.quoted_path(temp_dir)} ${os.quoted_path(os.abs_path(file_path))}'
	result := os.execute(command)
	if result.exit_code != 0 {
		os.rmdir_all(temp_dir) or {
			eprintln('Warning: failed to remove temporary directory ${temp_dir}: ${err}')
		}
		return error('TypeScript compilation failed:\n${result.output}')
	}

	output_file := os.join_path(temp_dir, '${os.file_name(file_path).all_before_last('.')}.js')
	if !os.exists(output_file) {
		os.rmdir_all(temp_dir) or {
			eprintln('Warning: failed to remove temporary directory ${temp_dir}: ${err}')
		}
		return error('TypeScript compiler succeeded but did not create ${output_file}')
	}

	return PreparedSource{
		path:     output_file
		temp_dir: temp_dir
	}
}
