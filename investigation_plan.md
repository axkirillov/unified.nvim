# Investigation Plan: Simplify `:Unified` Command

## Goal

Refactor the `:Unified` command in `unified.nvim` to simplify its usage. Remove subcommands and implement the following behavior:

*   `:Unified <commit_ref>`: Shows a diff view comparing the current buffer(s) against the specified `<commit_ref>`. Also displays a file tree showing files changed in that commit range. Preserves existing commit reference autocompletion.
*   `:Unified` (no arguments): Acts based on the current state:
    *   If the unified view is **not** currently active, it shows the diff against `HEAD` (equivalent to `:Unified HEAD`).
    *   If the unified view **is** currently active, it closes the view and removes highlights (deactivates).

## Detailed Plan

1.  **Modify `plugin/unified.lua`:**
    *   **Command Logic:**
        *   Inside the `nvim_create_user_command` callback function:
            *   Get the `args` from `opts.args`.
            *   Check `if args == "" then`:
                *   Inside this block, check `if require("unified.state").is_active then`:
                    *   Call `require("unified").deactivate()` to close the view.
                *   `else` (meaning `state.is_active` is false, this is the first call):
                    *   Call `require("unified").handle_commit_command("HEAD")` to show the diff against `HEAD`.
            *   `else` (meaning `args` is not empty):
                *   Call `require("unified").handle_commit_command(args)` to handle the specific commit reference.
        *   Remove all the original `elseif` blocks for `toggle`, `refresh`, `tree`, `debug`, and the final `else` block that called `activate()`.
    *   **Command Completion Logic:**
        *   Modify the completion function (originally lines 52-84).
        *   The condition checking for just `Unified ` (`line:match("^Unified%s+$")`) will be updated to return an empty list `{}` (removing the old subcommand suggestions like `toggle`, `refresh`, etc.).
        *   The condition that previously checked for `Unified commit ` (`line:match("^Unified%s+commit%s+")`) will be changed to check for `Unified ` followed by *any* character (`line:match("^Unified%s+.")`).
        *   **Crucially, the code block associated with this condition (lines 57-81), which checks if it's a git repo and returns suggestions like `HEAD`, `HEAD~1`, `main`, `master`, etc., will be kept.** This ensures the commit reference completion works for the simplified `Unified <commit_ref>` command.

2.  **Update Documentation (`README.md`, `doc/unified.txt`):**
    *   **Read:** Examine both files to find explanations of the `:Unified` command.
    *   **Rewrite:** Modify these sections to describe the new behavior accurately:
        *   `:Unified <commit_ref>`: Shows a diff view comparing the current buffer(s) against the specified `<commit_ref>`. Also displays a file tree showing files changed in that commit range.
        *   `:Unified` (no arguments): Acts based on the current state:
            *   If the unified view is **not** currently active, it shows the diff against `HEAD` (equivalent to `:Unified HEAD`).
            *   If the unified view **is** currently active, it closes the view and removes highlights.
    *   **Remove:** Delete all mentions of the previous subcommands (`toggle`, `refresh`, `tree`, `commit`, `debug`).

## Visual Plan (Mermaid)

```mermaid
graph TD
    A[Start: User Request] --> B{Analyze Request};
    B --> C{Gather Context};
    C --> C1[Search Cmd Defs];
    C1 --> C2[Read plugin/unified.lua];
    C2 --> C3[Read lua/unified/init.lua];
    C3 --> C4[Read lua/unified/commit.lua];
    C4 --> D{Refine Understanding};
    D --> D_Clarification{User Clarification: Behavior of `:Unified` (no args)};
    D_Clarification --> E{Create Updated Detailed Plan};
    E --> E1[Modify plugin/unified.lua];
    E --> E2[Update README.md];
    E --> E3[Update doc/unified.txt];
    E --> F{Present Updated Plan to User};
    F -- Approved --> G{Ask to Write Plan to File};
    G -- Yes --> H[Write plan.md];
    H --> I{Switch to Code Mode};
    G -- No --> I;
    F -- Changes Needed --> E;

    subgraph "Step E1: Modify plugin/unified.lua"
        direction LR
        E1_1[Check `if args == ""`] --> E1_2{Check `state.is_active`};
        E1_2 -- true --> E1_3[Call `deactivate()`];
        E1_2 -- false --> E1_4[Call `handle_commit_command("HEAD")`];
        E1_1 -- else (`args ~= ""`) --> E1_5[Call `handle_commit_command(args)`];
        E1_5 --> E1_6[Remove old subcommand logic];
        E1_6 --> E1_7[Update command completion logic (Preserve commit ref completion)];
    end

    subgraph "Step E2/E3: Update Documentation"
        direction LR
        E2_1[Read Docs] --> E2_2[Identify Command Sections];
        E2_2 --> E2_3[Rewrite for New Behavior: `:Unified <ref>` and `:Unified` (HEAD/Close)];
        E2_3 --> E2_4[Remove Old Subcommand Refs];
    end