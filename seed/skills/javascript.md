---
name: javascript
triggers: javascript, typescript, const, let, async, await, promise, undefined, nan, .js, .ts
---
Usual causes in JavaScript, worth checking against the code:
- A promise used as its value: `fetch(...)` or an async call without `await`.
- A misspelt property name, which reads as `undefined` and turns sums into `NaN`.
- `this` lost in a callback; an arrow function keeps it.
- `==` where `===` was meant, or comparing objects by identity.
- A variable read before an async callback has set it.
