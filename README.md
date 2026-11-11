# vos

`vos` is a V command-line project that executes JavaScript and TypeScript using
[herudi.vjs](https://github.com/herudi/vjs), V bindings for the QuickJS engine.
JavaScript runs directly in QuickJS. TypeScript is type-checked and transpiled
to JavaScript by the TypeScript compiler before QuickJS runs it.

## Requirements

- [V](https://vlang.io/)
- A C compiler supported by V (GCC is recommended; on Windows, use MSYS2 UCRT64 GCC)
- TypeScript compiler (`tsc`) for `.ts` files
- Node.js and npm to install TypeScript for `.ts` files

On Windows, open an MSYS2 UCRT64 shell or add its tools to `PATH` in
PowerShell. The `-U_TRUNCATE` flag is needed for MinGW builds. On Linux and
macOS, use the commands without that Windows-specific flag.

PowerShell (Windows):

```powershell
$env:Path = "C:\msys64\ucrt64\bin;C:\msys64\usr\bin;$env:Path"
v -cc gcc -cflags "-U_TRUNCATE" test .
```

Linux or macOS:

```sh
v test .
```

Install the V dependency from this project:

```sh
v install
```

Install TypeScript if it is not already available on your `PATH`:

```sh
npm install --global typescript
```

## Run

Windows (PowerShell):

```powershell
v -cc gcc -cflags "-U_TRUNCATE" run . path\to\script.js
v -cc gcc -cflags "-U_TRUNCATE" run . path\to\script.ts
```

Linux or macOS:

```sh
v run . path/to/script.js
v run . path/to/script.ts
```

## Serve a website

Use `vos serve` to start a local HTTP server for an HTML page and its sibling
static assets:

```sh
vos serve examples/website/page.html
```

By default, the server listens on `127.0.0.1:3000`. Open
<http://127.0.0.1:3000/> in a browser. The requested HTML file is served at `/`,
and files beside it (such as CSS, JavaScript, and images) are served by their
relative paths.

To select a different address or port, provide `host:port` after the HTML path:

```sh
vos serve examples/website/page.html 127.0.0.1:8080
```

Use `--profile` to print per-request status, elapsed time, and file resolution
and read timings to the terminal:

```sh
vos serve examples/website/page.html --profile
```

## Install npm packages

Install an npm package for vos without adding it to the current project's
`node_modules`:

```sh
vos install npm:lodash
vos install npm:@types/node
```

You can also download a JavaScript or TypeScript module directly from an HTTP
or HTTPS URL:

```sh
vos install https://example.com/path/to/module.ts
```

Packages are installed under vos's per-user application data directory
(`vos/node_modules`), with a separate package manifest and lockfile, independent
of the current working directory and project. Node.js and npm must be available
on `PATH` for npm packages. URL modules are cached under
`vos/remote_modules` in the same application data directory.

JavaScript and TypeScript ES modules can import local files with relative
specifiers and installed packages by their npm package name:

```js
import { greeting } from "./greeting.js";
import { someFunction } from "some-package";
```

`vos` resolves project-local `node_modules` first, then packages installed with
`vos install`. TypeScript is transpiled to ES2015 JavaScript while preserving
ES module imports. Imported packages must provide JavaScript ES modules; Node.js
built-in modules and CommonJS-only packages are not provided by QuickJS.

## Create a TypeScript project

Create a project directory and install TypeScript locally:

```sh
vos new my-project
cd my-project
vos src/index.ts
```

Running `vos new` without a name sets up the current directory, using its
directory name for the npm package name. The command creates `package.json`,
`src/index.ts`, and a local TypeScript installation. `vos` uses that local
compiler when running TypeScript files in the project; otherwise it falls back
to `tsc` on `PATH`. A CLI process cannot change the parent shell's directory,
so use the printed `cd` command after creating a named project.

To build a standalone executable, use the Windows command in PowerShell or
the Linux/macOS command in a shell:

```powershell
v -cc gcc -cflags "-U_TRUNCATE" -o vos .
.\vos.exe path\to\script.ts
```

```sh
v -o vos .
./vos path/to/script.ts
```

The runner exposes `console` through `herudi.vjs.web`. QuickJS does not provide
Node.js APIs. Local ES module imports work in JavaScript and TypeScript.
TypeScript type errors are reported before execution.
