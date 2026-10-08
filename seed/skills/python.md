---
name: python
triggers: python, def, traceback, indexerror, keyerror, typeerror, attributeerror, .py
---
Usual causes in Python, worth checking against the code:
- A loop or index one past the end: `range(len(x) + 1)`, `x[len(x)]`.
- A total or list overwritten (`=`) where it should grow (`+=`, `append`).
- A function that prints instead of returning, so its caller gets `None`.
- A default argument that is a list or dict, shared between calls.
- The last line of a traceback names the error; the line above it is where it happened.
