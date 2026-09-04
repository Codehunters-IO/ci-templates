## What changes

<!-- What a consumer would notice. Not a file list -- the diff already says that. -->

## Why

<!-- The problem this solves. If it fixes a defect, how it reached production. -->

## Consumer impact

<!-- Everything here ships to every repository pinned to @v1 on the next release. -->

- [ ] No change for existing callers (new optional input, internal refactor, docs)
- [ ] Behaviour changes for existing callers — describe the migration below
- [ ] New required input or secret — name it below

<!-- If either box below the first is ticked, say what a caller has to do and by when. -->

## Version

<!-- Every push to main cuts a release and moves the floating v1 alias. -->

- [ ] patch — fix, no interface change
- [ ] minor — new optional input, new workflow
- [ ] major — removed or renamed input, changed default, removed workflow (freezes v1)

## Verification

<!-- What you actually ran. "actionlint passes" is worth more than "looks fine". -->

- [ ] `actionlint` reports no errors
- [ ] Exercised against a real consumer repository, or explained why not
