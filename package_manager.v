module main

import crypto.sha256
import net.http
import net.urllib
import os

const remote_module_extensions = ['.js', '.mjs', '.cjs', '.ts', '.mts', '.cts', '.jsx', '.tsx']

fn parse_remote_module_url(raw_url string) !urllib.URL {
	parsed := urllib.parse(raw_url) or {
		return error('Invalid module URL "${raw_url}": ${err.msg()}')
	}
	if parsed.scheme.to_lower() !in ['http', 'https'] || parsed.host == '' {
		return error('Invalid module URL "${raw_url}". Use an http or https URL.')
	}
	if user := parsed.user {
		if user.username != '' || user.password != '' {
			return error('Module URLs with embedded credentials are not supported.')
		}
	}
	return parsed
}

fn remote_module_cache_path(raw_url string) !string {
	parsed := parse_remote_module_url(raw_url)!
	url_extension := os.file_ext(parsed.path).to_lower()
	extension := if url_extension in remote_module_extensions { url_extension } else { '.js' }
	cache_dir := os.join_path(npm_application_directory(), 'remote_modules',
		sha256.sum(raw_url.bytes()).hex())
	return os.join_path(cache_dir, 'module${extension}')
}

fn install_remote_module(raw_url string) ! {
	parse_remote_module_url(raw_url)!
	response := http.get(raw_url)!
	if response.status_code < 200 || response.status_code >= 300 {
		return error('Downloading module from ${raw_url} failed with HTTP ${response.status_code}.')
	}

	module_path := remote_module_cache_path(raw_url)!
	os.mkdir_all(os.dir(module_path))!
	os.write_file(module_path, response.body)!
	println('Downloaded ${raw_url} to ${module_path}.')
}

fn valid_npm_name_segment(segment string) bool {
	if segment.len == 0 || segment[0] in [u8(`.`), u8(`_`), u8(`-`)]
		|| segment[segment.len - 1] == u8(`.`) {
		return false
	}

	for code in segment.bytes() {
		if !(code >= u8(`a`) && code <= u8(`z`)) && !(code >= u8(`0`) && code <= u8(`9`))
			&& code !in [u8(`-`), u8(`_`), u8(`.`)] {
			return false
		}
	}
	return true
}

fn parse_npm_package_specifier(specifier string) !string {
	if !specifier.starts_with('npm:') {
		return error('Unsupported package source "${specifier}". Use npm:<package-name>.')
	}

	name := specifier.all_after('npm:')
	if name.len == 0 || name.len > 214 {
		return error('Invalid npm package name "${name}".')
	}

	if name.starts_with('@') {
		parts := name[1..].split('/')
		if parts.len != 2 || !valid_npm_name_segment(parts[0]) || !valid_npm_name_segment(parts[1]) {
			return error('Invalid scoped npm package name "${name}". Use @scope/package-name.')
		}
	} else if name.contains('/') || !valid_npm_name_segment(name) {
		return error('Invalid npm package name "${name}".')
	}

	return name
}

fn npm_application_directory() string {
	return os.join_path(os.data_dir(), 'vos')
}

fn npm_command() !string {
	$if windows {
		npm_path := os.find_abs_path_of_executable('npm.cmd')!
		node_path := os.find_abs_path_of_executable('node.exe')!
		npm_cli_path := os.join_path(os.dir(npm_path), 'node_modules', 'npm', 'bin', 'npm-cli.js')
		if !os.exists(npm_cli_path) {
			return error('Could not locate npm-cli.js next to ${npm_path}.')
		}
		return '${os.quoted_path(node_path)} ${os.quoted_path(npm_cli_path)}'
	}
	return os.quoted_path('npm')
}

fn ensure_npm_manifest(application_dir string) ! {
	manifest_path := os.join_path(application_dir, 'package.json')
	if !os.exists(manifest_path) {
		os.write_file(manifest_path,
			'{\n\t"name": "vos-packages",\n\t"version": "1.0.0",\n\t"private": true\n}\n')!
	}
}

fn install_npm_package(specifier string) ! {
	package_name := parse_npm_package_specifier(specifier)!
	application_dir := npm_application_directory()
	os.mkdir_all(application_dir)!
	ensure_npm_manifest(application_dir)!

	npm := npm_command()!
	command := '${npm} install --prefix ${os.quoted_path(application_dir)} ${os.quoted_path(package_name)}'
	result := os.execute(command)
	if result.exit_code != 0 {
		return error('npm install failed (exit code ${result.exit_code}):\n${result.output}')
	}
	if result.output != '' {
		print(result.output)
	}

	println('Installed ${package_name} to ${os.join_path(application_dir, 'node_modules')}.')
}

fn install_package(specifier string) ! {
	if specifier.to_lower().starts_with('http://') || specifier.to_lower().starts_with('https://') {
		install_remote_module(specifier)!
		return
	}
	install_npm_package(specifier)!
}

fn validate_project_directory_name(name string) ! {
	if name == '' || name in ['.', '..'] || name.contains('/') || name.contains('\\')
		|| os.is_abs_path(name) {
		return error('Invalid project name "${name}". Provide a single directory name.')
	}
}

fn npm_project_name(name string) !string {
	normalized := name.to_lower().replace(' ', '-')
	if !valid_npm_name_segment(normalized) || normalized.len > 214 {
		return error('Project name "${name}" cannot be used as an npm package name.')
	}
	return normalized
}

fn create_typescript_project(project_name string) ! {
	current_dir := os.getwd()
	is_current_dir := project_name == ''
	if !is_current_dir {
		validate_project_directory_name(project_name)!
	}

	directory_name := if is_current_dir { os.file_name(current_dir) } else { project_name }
	if directory_name == '' {
		return error('Could not determine a project name from the current directory.')
	}
	package_name := npm_project_name(directory_name)!
	project_dir := if is_current_dir {
		current_dir
	} else {
		os.join_path(current_dir, project_name)
	}

	if !is_current_dir && os.exists(project_dir) {
		return error('Directory already exists: ${project_dir}')
	}
	if is_current_dir {
		if os.exists(os.join_path(project_dir, 'package.json')) {
			return error('A package.json already exists in ${project_dir}.')
		}
		if os.exists(os.join_path(project_dir, 'src', 'index.ts')) {
			return error('A src/index.ts already exists in ${project_dir}.')
		}
	}

	os.mkdir_all(project_dir)!
	os.write_file(os.join_path(project_dir, 'package.json'),
		'{\n\t"name": "${package_name}",\n\t"version": "1.0.0",\n\t"private": true,\n\t"type": "module",\n\t"devDependencies": {}\n}\n')!
	os.mkdir_all(os.join_path(project_dir, 'src'))!
	os.write_file(os.join_path(project_dir, 'src', 'index.ts'),
		'console.log("Hello from TypeScript!");\n')!

	npm := npm_command()!
	command := '${npm} install --prefix ${os.quoted_path(project_dir)} --save-dev typescript'
	result := os.execute(command)
	if result.exit_code != 0 {
		return error('Failed to install TypeScript (exit code ${result.exit_code}):\n${result.output}')
	}
	if result.output != '' {
		print(result.output)
	}

	println('Created TypeScript project in ${project_dir}.')
	if !is_current_dir {
		println('Next: cd ${os.quoted_path(project_name)}')
	}
	println('Run it with: vos src/index.ts')
}
