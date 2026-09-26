// Flat config for the repository's small deterministic Node scripts.
//
// The host application (index.js, pair.js) is legacy and deliberately NOT in
// scope here: it is syntax-checked (`node --check`) and invariant-tested
// (scripts/test-agent-invariants.js) instead. Linting stays restricted to the
// scripted checks that the CI harness itself runs so it can never block a fix
// on pre-existing legacy debt.

const js = require("@eslint/js");

module.exports = [
  {
    ignores: ["node_modules/**"],
  },
  js.configs.recommended,
  {
    files: ["scripts/**/*.js", "eslint.config.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: {
        console: "readonly",
        require: "readonly",
        module: "readonly",
        process: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        Buffer: "readonly",
        JSON: "readonly",
        Math: "readonly",
        Date: "readonly",
        URL: "readonly",
        TextDecoder: "readonly",
        AbortController: "readonly",
        fetch: "readonly",
      },
    },
    rules: {
      "no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    },
  },
];