module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'refactor', 'test', 'docs', 'chore', 'ci', 'style', 'perf', 'build', 'revert'
    ]],
    'type-empty': [2, 'never'],
    'type-case': [2, 'always', 'lower-case'],
    'subject-empty': [2, 'never'],
    'subject-max-length': [2, 'always', 100],
    'subject-full-stop': [2, 'never', '.'],
    'header-max-length': [2, 'always', 120],
    'body-max-line-length': [1, 'always', 200],
    // A squash merge concatenates every commit message, so the first trailer
    // (Co-Authored-By, Signed-off-by) turns the rest of the bodies into the
    // "footer". Erroring there fails the release PR on commits already merged
    // and impossible to reword. Warn, like the body rule.
    'footer-max-line-length': [1, 'always', 200],
    'scope-case': [2, 'always', 'lower-case'],
  },
};
