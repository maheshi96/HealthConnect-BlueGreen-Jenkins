"use strict";

const security = require("eslint-plugin-security");

module.exports = [
  {
    files: ["app/**/*.js", "tests/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: {
        Buffer: "readonly",
        console: "readonly",
        describe: "readonly",
        expect: "readonly",
        module: "readonly",
        process: "readonly",
        require: "readonly",
        setTimeout: "readonly",
        test: "readonly"
      }
    },
    plugins: { security },
    rules: {
      ...security.configs.recommended.rules,
      "no-constant-condition": "error",
      "no-unused-vars": ["error", { "argsIgnorePattern": "^_" }]
    }
  }
];
