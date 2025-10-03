# Proposal: Fix Nested `\substack` in Subscripts

## Problem Analysis

### Current Status
- ✅ `\substack{a \\ b}` works correctly
- ❌ `\sum_{\substack{a \\ b}}` fails with "Missing closing brace"
- ❌ `\prod_{\substack{p \text{ prime} \\ p < 100}}` fails

### Root Cause

The current implementation in `MTMathListBuilder.swift:748-808` has a fundamental flaw in how it handles brace parsing when `\substack` is nested inside other constructs.

#### The Issue

When parsing `\sum_{\substack{a \\ b}}`, the execution flow is:

1. **Subscript Parser** calls `buildInternal(true)` which:
   - Sees `{`
   - Calls `buildInternal(false, stopChar: "}")` expecting to find the subscript's closing `}`

2. **Inside subscript content**, `\substack` command is encountered:
   - Substack handler manually consumes `{` (line 754)
   - Sets up `currentEnv = "substack"` (line 761)
   - Loops calling `buildInternal(false)` (line 778)
   - When `buildInternal(false)` sees `}`, it returns due to substack environment check (line 370-372)
   - Substack handler then consumes this `}` (line 773)
   - **PROBLEM**: This `}` might be consumed incorrectly depending on context

3. **The outer `buildInternal(false, stopChar: "}")` continues**:
   - It's looking for the subscript's closing `}`
   - But the substack may have consumed characters in a way that breaks the parse state

#### Why It Fails

The core issue is **manual brace handling** in the substack parser conflicts with the standard `buildInternal` brace tracking:

```swift
// Line 754: Manual consumption
if !hasCharacters || getNextCharacter() != "{" {
    setError(.mismatchBraces, message: "Missing { after \\substack")
    return nil
}
```

This manual `getNextCharacter()` breaks the invariant that `buildInternal` maintains about character positions. When `buildInternal(false, stopChar: "}")` is called for the subscript content, it expects the opening `{` to still be in the stream or to be handled by the standard `{` case (line 355-364).

## Proposed Solution

### Option 1: Use Standard `buildInternal(true)` Pattern (RECOMMENDED)

**Key Insight**: Commands like `\frac`, `\text`, `\accent` all use `buildInternal(true)` to read their braced arguments. We should do the same for `\substack`.

**Implementation**:

```swift
} else if command == "substack" {
    // \substack reads ONE braced argument containing rows separated by \\
    // Similar to how \frac reads {numerator}{denominator}

    // Set up environment BEFORE reading the argument
    let oldEnv = self.currentEnv
    currentEnv = MTEnvProperties(name: "substack")

    // Read the braced content using standard pattern
    let content = self.buildInternal(true)

    currentEnv = oldEnv

    if content == nil {
        return nil
    }

    // The content may already be a table if \\ was encountered
    // Check if we got a table from the \\ parsing
    if content!.atoms.count == 1, let tableAtom = content!.atoms.first as? MTMathTable {
        return tableAtom
    }

    // Otherwise, single row - wrap in table
    var rows = [[MTMathList]]()
    rows.append([content!])

    var error: NSError? = self.error
    let table = MTMathAtomFactory.table(withEnvironment: nil, rows: rows, error: &error)
    if table == nil && self.error == nil {
        self.error = error
        return nil
    }

    return table
}
```

**Why This Works**:

1. **Leverages existing infrastructure**: `buildInternal(true)` properly handles:
   - Finding and consuming the `{` (line 355-357)
   - Parsing content with `buildInternal(false, stopChar: "}")`
   - Finding and consuming the matching `}`
   - Returning exactly one "argument"

2. **Respects parse state**: No manual character consumption that could break invariants

3. **Handles nesting naturally**: When `\text{...}` appears inside substack, the standard brace handling just works

4. **Works with `\\` naturally**: When `\\` is encountered inside the braced content:
   - The `stopCommand` function (line 1019) handles it
   - It increments `currentEnv.numRows`
   - Might create an implicit table
   - This is exactly what we want!

5. **Minimal code**: Much simpler than manual parsing loop

### Option 2: Fix Brace Depth Tracking (COMPLEX, NOT RECOMMENDED)

Add explicit brace depth counter to track nested `{}` pairs:

```swift
} else if command == "substack" {
    skipSpaces()
    if !hasCharacters || getNextCharacter() != "{" {
        setError(.mismatchBraces, message: "Missing { after \\substack")
        return nil
    }

    let oldEnv = self.currentEnv
    currentEnv = MTEnvProperties(name: "substack")

    var rows = [[MTMathList]]()
    var currentRow = 0
    rows.append([MTMathList]())

    var braceDepth = 1  // We just consumed the opening brace

    while self.hasCharacters && braceDepth > 0 {
        let char = string[currentCharIndex]

        // Track brace depth BEFORE calling buildInternal
        if char == "{" {
            braceDepth += 1
        } else if char == "}" {
            braceDepth -= 1
            if braceDepth == 0 {
                _ = getNextCharacter() // consume final }
                break
            }
        }

        let list = self.buildInternal(false)
        if list == nil {
            currentEnv = oldEnv
            return nil
        }

        if !list!.atoms.isEmpty {
            rows[currentRow].append(list!)
        }

        if currentEnv!.numRows > currentRow {
            currentRow = currentEnv!.numRows
            rows.append([MTMathList]())
        }
    }

    currentEnv = oldEnv
    // ... create table ...
}
```

**Problems with this approach**:
- Doesn't account for braces consumed by `buildInternal`
- `buildInternal` may consume multiple characters including braces
- Brace depth checking BEFORE calling `buildInternal` doesn't help since `buildInternal` will move the position
- Very complex and error-prone

### Option 3: Pass Stop Function Instead of Environment Check

Create a closure-based stop condition:

**NOT RECOMMENDED** - Would require significant refactoring of `buildInternal` signature.

## Recommendation

**Implement Option 1** - it's:
- ✅ Simple and clean
- ✅ Follows established patterns (`\frac`, `\text`)
- ✅ Handles all nesting scenarios correctly
- ✅ Minimal code changes
- ✅ Easy to test and maintain

## Testing Strategy

After implementing Option 1, test these cases:

```swift
// Basic
"\\substack{a \\\\ b}"  // Should work (already works)

// In subscript (currently broken)
"x_{\\substack{a \\\\ b}}"
"\\sum_{\\substack{0 \\le i \\le m \\\\ 0 < j < n}}"

// With nested commands (currently broken)
"\\prod_{\\substack{p \\text{ prime} \\\\ p < 100}}"
"\\substack{\\frac{a}{b} \\\\ c}"

// Multiple levels
"\\sum_{\\substack{i=1 \\\\ j \\ne i}}^{\\substack{n \\\\ m}}"

// Edge cases
"\\substack{a}"  // Single row
"\\substack{}"   // Empty (should handle gracefully)
"\\substack{a \\\\ b \\\\ c \\\\ d}"  // Many rows
```

## Implementation Steps

1. **Backup current implementation** (for comparison)
2. **Replace substack handler** with Option 1 code
3. **Remove special `}` handling** for substack environment (line 370-372) since it won't be needed
4. **Run existing tests** to ensure no regressions
5. **Add new tests** for nested cases
6. **Update MISSING_FEATURES.md** to mark as fully implemented

## Expected Outcome

After this fix:
- ✅ All substack cases work correctly
- ✅ Proper nesting with subscripts/superscripts
- ✅ Handles commands like `\text`, `\frac` inside substack
- ✅ Clean, maintainable code following SwiftMath patterns

## Alternative: If Option 1 Doesn't Handle `\\` Correctly

If `buildInternal(true)` doesn't properly create a table when `\\` is encountered, we may need to:

1. Check if `content.atoms.count == 1` and first atom is a table
2. If not a table, manually split the content by looking for row breaks
3. Create table structure manually

But this is unlikely - the existing code should handle `\\` creating tables within the braced content.

---

**Decision**: Proceed with Option 1 implementation.
**Risk Level**: Low (follows proven patterns)
**Effort**: ~30 minutes
**Benefit**: Fully working `\substack` command
