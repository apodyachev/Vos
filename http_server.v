module main

import net.http
import net.urllib
import os

// WebPageHandler serves an HTML page and the static assets beside it.
struct WebPageHandler {
	root      string
	page_name string
}

fn (mut handler WebPageHandler) handle(req http.Request) http.Response {
	request_path := req.url.all_before('?')
	decoded_path := urllib.path_unescape(request_path) or {
		return not_found_response()
	}
	if !decoded_path.starts_with('/') || decoded_path.contains('\\') || decoded_path.contains('\x00') {
		return not_found_response()
	}
	for segment in decoded_path.split('/') {
		if segment in ['.', '..'] {
			return not_found_response()
		}
	}
	relative_path := if decoded_path == '/' {
		handler.page_name
	} else {
		decoded_path.trim_left('/')
	}
	file_path := os.join_path(handler.root, relative_path)
	resolved_path := os.real_path(file_path)
	root_prefix := handler.root + os.path_separator
	if resolved_path != handler.root && !resolved_path.starts_with(root_prefix) {
		return not_found_response()
	}
	body := os.read_file(resolved_path) or {
		return not_found_response()
	}
	content_type := content_type_for(resolved_path)
	return http.Response{
		status_code: 200
		status_msg:  'OK'
		header:      http.new_header(key: .content_type, value: content_type)
		body:        body
	}
}

fn not_found_response() http.Response {
	return http.Response{
		status_code: 404
		status_msg:  'Not Found'
		header:      http.new_header(key: .content_type, value: 'text/plain; charset=utf-8')
		body:        'Not Found'
	}
}

fn content_type_for(file_path string) string {
	return match os.file_ext(file_path).to_lower() {
		'.html', '.htm' { 'text/html; charset=utf-8' }
		'.css' { 'text/css; charset=utf-8' }
		'.js', '.mjs' { 'text/javascript; charset=utf-8' }
		'.json', '.map' { 'application/json; charset=utf-8' }
		'.svg' { 'image/svg+xml' }
		'.png' { 'image/png' }
		'.jpg', '.jpeg' { 'image/jpeg' }
		'.gif' { 'image/gif' }
		'.ico' { 'image/x-icon' }
		'.woff' { 'font/woff' }
		'.woff2' { 'font/woff2' }
		else { 'application/octet-stream' }
	}
}

// serve_page reads an HTML entrypoint and serves it and its sibling assets.
fn serve_page(file_path string, address string) ! {
	if os.file_ext(file_path).to_lower() !in ['.html', '.htm'] {
		return error('Expected an HTML file: ${file_path}')
	}
	if !os.is_file(file_path) {
		return error('HTML file does not exist: ${file_path}')
	}
	root := os.real_path(os.dir(os.abs_path(file_path)))
	page_name := os.file_name(file_path)
	mut server := http.Server{
		addr:    address
		handler: WebPageHandler{
			root:      root
			page_name: page_name
		}
	}
	server.listen_and_serve()
}
