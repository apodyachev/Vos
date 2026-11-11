module main

import os
import time
import json
import herudi.vjs

#flag @VMODROOT/module_resolver.c

struct PreparedSource {
	path     string
	temp_dir string
}

struct PackageMetadata {
	main   string
	module string
}

type ModuleNormalizeFunc = fn (voidptr, &char, &char, voidptr) &char

fn C.vos_set_module_loader(voidptr, &ModuleNormalizeFunc)
fn C.vos_js_strdup(voidptr, &char) &char

fn find_local_typescript_compiler(file_path string) string {
	mut directory := os.dir(os.abs_path(file_path))
	for {
		compiler_path := os.join_path(directory, 'node_modules', 'typescript', 'bin', 'tsc')
		if os.exists(compiler_path) {
			return compiler_path
		}
		parent := os.dir(directory)
		if parent == directory {
			return ''
		}
		directory = parent
	}
	return ''
}

fn resolve_module_file(candidate string, package_root string) string {
	path := os.abs_path(candidate)
	if path != package_root && !path.starts_with('${package_root}${os.path_separator}') {
		return ''
	}
	if os.is_file(path) {
		return path
	}

	if os.is_dir(path) {
		metadata_path := os.join_path(path, 'package.json')
		if os.exists(metadata_path) {
			metadata_contents := os.read_file(metadata_path) or { '' }
			if metadata_contents != '' {
				metadata := json.decode(PackageMetadata, metadata_contents) or { PackageMetadata{} }
				for entry in [metadata.module, metadata.main] {
					if entry != '' {
						resolved := resolve_module_file(os.join_path(path, entry), package_root)
						if resolved != '' {
							return resolved
						}
					}
				}
			}
		}
		for entry in ['index.js', 'index.mjs'] {
			resolved := resolve_module_file(os.join_path(path, entry), package_root)
			if resolved != '' {
				return resolved
			}
		}
		return ''
	}

	if os.file_ext(path) == '' {
		for extension in ['.js', '.mjs'] {
			resolved := resolve_module_file(path + extension, package_root)
			if resolved != '' {
				return resolved
			}
		}
	}
	return ''
}

fn split_package_specifier(specifier string) !(string, string) {
	parts := specifier.split('/')
	mut package_parts := 1
	if specifier.starts_with('@') {
		if parts.len < 2 || parts[0].len < 2 || parts[1] == '' {
			return error('Invalid package import "${specifier}".')
		}
		package_parts = 2
	}
	if parts.len < package_parts {
		return error('Invalid package import "${specifier}".')
	}
	for part in parts {
		if part in ['', '.', '..'] {
			return error('Invalid package import "${specifier}".')
		}
	}
	package_name := parts[..package_parts].join('/')
	subpath := if parts.len > package_parts { parts[package_parts..].join('/') } else { '' }
	return package_name, subpath
}

fn resolve_npm_module(base_path string, specifier string) string {
	package_name, subpath := split_package_specifier(specifier) or { return '' }
	search_directories := [os.dir(os.abs_path(base_path)), os.getwd()]
	for search_directory in search_directories {
		mut directory := search_directory
		for {
			node_modules := if os.file_name(directory) == 'node_modules' {
				directory
			} else {
				os.join_path(directory, 'node_modules')
			}
			package_root := os.join_path(node_modules, package_name)
			if os.is_dir(package_root) {
				candidate := if subpath == '' {
					package_root
				} else {
					os.join_path(package_root, subpath)
				}
				resolved := resolve_module_file(candidate, os.abs_path(package_root))
				if resolved != '' {
					return resolved
				}
			}
			parent := os.dir(directory)
			if parent == directory {
				break
			}
			directory = parent
		}
	}

	global_package_root := os.join_path(npm_application_directory(), 'node_modules', package_name)
	candidate := if subpath == '' {
		global_package_root
	} else {
		os.join_path(global_package_root, subpath)
	}
	return resolve_module_file(candidate, os.abs_path(global_package_root))
}

fn resolve_module_specifier(base_name string, specifier string) string {
	if specifier.starts_with('.') {
		base_path := if os.is_abs_path(base_name) { base_name } else { os.abs_path(base_name) }
		return os.abs_path(os.join_path(os.dir(base_path), specifier))
	}
	if os.is_abs_path(specifier) {
		return os.abs_path(specifier)
	}
	return resolve_npm_module(base_name, specifier)
}

fn normalize_module_name(ctx voidptr, base_name &char, module_name &char, _ voidptr) &char {
	base := unsafe { cstring_to_vstring(base_name) }
	specifier := unsafe { cstring_to_vstring(module_name) }
	resolved := resolve_module_specifier(base, specifier)
	if resolved == '' {
		return C.vos_js_strdup(ctx, module_name)
	}
	return C.vos_js_strdup(ctx, resolved.str)
}

fn configure_module_loader(rt vjs.Runtime) {
	// vjs keeps Runtime.ref private; the C shim unwraps its single-pointer handle.
	C.vos_set_module_loader(unsafe { voidptr(&rt) }, &normalize_module_name)
}

fn prepare_source(file_path string) !PreparedSource {
	if os.file_ext(file_path).to_lower() != '.ts' {
		return PreparedSource{
			path: os.abs_path(file_path)
		}
	}

	temp_dir := os.join_path(os.temp_dir(), 'vos_${os.getpid()}_${time.now().unix_nano()}')
	os.mkdir_all(temp_dir)!

	local_compiler := find_local_typescript_compiler(file_path)
	compiler_command := if local_compiler != '' {
		'${os.quoted_path('node')} ${os.quoted_path(local_compiler)}'
	} else {
		os.quoted_path('tsc')
	}
	command := '${compiler_command} --target ES2015 --module ESNext --moduleResolution Bundler --skipLibCheck --outDir ${os.quoted_path(temp_dir)} ${os.quoted_path(os.abs_path(file_path))}'
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
