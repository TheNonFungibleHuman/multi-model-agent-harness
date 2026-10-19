# Verification (home rules — apply in every session)

## Before you declare a code change done
1. **Symbol sweep, not filename sweep.** List the classes/functions you touched; grep the test tree for each name and run every test module that references it. A module named after the file you edited is not enough — one class is often exercised from several test files.
2. **Use the project's own environment first.** Find its venv or test runner (`.venv`, `venv`, tox.ini, CONTRIBUTING) and run tests with that interpreter. Only conclude "tests can't run" after quoting the exact command and error that blocked you; then fall back to the narrowest scripted repro.
3. **Sweep the neighborhood.** When the task makes validation or behavior stricter, search the same area for similar checks (asserts, silent returns) and bring them to the same standard when that is clearly the intent — do not implement only the literal issue text.
4. **End with evidence.** Final summary: files changed + exact test command(s) run + result (or what blocked it). Never claim done without this line.
