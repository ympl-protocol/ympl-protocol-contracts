module.exports = {
    "extends": ["standard"],
    "env": {
        "node": true,
    },
    "parserOptions": {
      "ecmaVersion": 8,
    },
    "globals": {
      "artifacts": true,
      "assert": true,
      "contract": true,
      "expect": true,
      "Promise": true,
      "web3": true,
    },
    "rules": {
      "semi": 0
    },
}
