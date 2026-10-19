# vos

`vos` is a V command-line project that executes JavaScript and TypeScript using
[herudi.vjs](https://github.com/herudi/vjs), V bindings for the QuickJS engine.
JavaScript runs directly in QuickJS. TypeScript is type-checked and transpiled
to JavaScript by the TypeScript compiler before QuickJS runs it.

## Requirements

- [V](https://vlang.io/)
- GCC (on Windows, use MSYS2 UCRT64 GCC)
- TypeScript compiler (`tsc`) for `.ts` files
- Node.js and npm to install TypeScript for `.ts` files

For Windows, open an MSYS2 UCRT64 shell or prepend its tools to `PATH` in
PowerShell. The `-U_TRUNCATE` flag avoids selecting an MSVC-only mbedTLS
function in MinGW builds:

```powershell
$env:Path = "C:\msys64\ucrt64\bin;C:\msys64\usr\bin;$env:Path"
v -cc gcc -cflags "-U_TRUNCATE" test .
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

```sh
v -cc gcc -cflags "-U_TRUNCATE" run . path/to/script.js
v -cc gcc -cflags "-U_TRUNCATE" run . path/to/script.ts
```

To build a standalone executable:

```sh
v -cc gcc -cflags "-U_TRUNCATE" -o vos .
.\vos.exe path\to\script.ts
```

The runner exposes `console` through `herudi.vjs.web`. QuickJS does not provide
Node.js APIs. Local ES module imports work in JavaScript and TypeScript.
TypeScript type errors are reported before execution.
