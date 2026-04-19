---
name: browser-control
description: How to drive the embedded browser — navigation workflow, interaction patterns, handoff to the user, and canvas mode for custom HTML.
category: Odyssey
triggers:
  - browser
  - navigate
  - browser_navigate
  - browser_click
  - web automation
  - open url
  - render html
  - yield to user
---

# Browser Control

You have access to an embedded browser running inside the user's chat. The user sees the browser in real-time in a side panel. Keep that in mind — every navigation and click is visible.

## The Tools at a Glance

| Tool | Purpose |
|---|---|
| `browser_navigate` | Load a URL |
| `browser_read_dom` | Read page structure as text |
| `browser_screenshot` | Capture what's visible |
| `browser_click` | Click an element by CSS selector |
| `browser_type` | Type into an input field |
| `browser_scroll` | Scroll up or down |
| `browser_wait_for` | Wait for an element to appear |
| `browser_get_console_logs` | Get JS console output |
| `browser_get_network_logs` | Get network requests/responses |
| `browser_yield_to_user` | Hand control to the user and wait |
| `browser_render_html` | Load custom HTML and wait for submission |

## Standard Navigation Workflow

For most web tasks, follow this sequence:

1. `browser_navigate(url: ...)` — load the page
2. `browser_wait_for(selector: "body")` — confirm page settled
3. `browser_read_dom()` — understand the structure without a screenshot
4. Interact (`browser_click`, `browser_type`, `browser_scroll`) as needed
5. `browser_read_dom()` or `browser_screenshot()` after significant state changes to verify the result

Use `browser_read_dom` first — it's text-based and costs less than a screenshot. Reserve `browser_screenshot` for visual verification (layout, images, colour, captchas).

## Interacting With Elements

Always read the DOM first to find the right selector. Don't guess.

```
browser_read_dom()
→ finds: <button id="submit-btn" class="primary">Submit</button>

browser_click(selector: "#submit-btn")
```

After a click that triggers navigation or dynamic content:
```
browser_wait_for(selector: ".results-container", timeoutMs: 8000)
browser_read_dom()
```

## Credentials and Login

**Never type passwords.** Use `browser_yield_to_user` whenever a page requires authentication:

```
browser_yield_to_user(message: "Please log in to your account, then click Resume when you're ready.")
```

This hands the browser to the user, shows your message, and blocks until they resume. Use this for:
- Login forms
- CAPTCHAs
- Two-factor authentication
- Any action that requires the user's personal credentials

## Handing Control to the User

Use `browser_yield_to_user` whenever the user needs to do something the agent can't or shouldn't automate:

```
browser_yield_to_user(message: "The checkout requires payment details. Please complete the purchase and click Resume.")
```

The user takes over the live browser, does their thing, then clicks Resume. Your tool call unblocks and you continue from the new page state. Read the DOM after resuming to understand where you are.

## Canvas Mode — Custom HTML

Use `browser_render_html` when you want to show the user a custom interface and collect structured input:

```
browser_render_html(
  html: "<h2>Select the items to export</h2><form>...<button onclick=\"window.agent.submit(JSON.stringify(selected))\">Export</button></form>",
  title: "Export Items"
)
→ blocks → user selects items and submits → returns: "User resumed from rendered HTML. Submitted data: [\"row-1\",\"row-3\"]"
```

The user submits by calling `window.agent.submit(data)` from the page's JavaScript. Design your HTML so the submit button calls `window.agent.submit(JSON.stringify(yourData))`. The submitted value is returned as the tool result.

Use canvas mode for:
- Presenting a table for the user to review/select rows
- Collecting structured form input
- Showing a preview before committing a destructive action
- Any UI that's easier to understand visually than in text

## Debugging

When a page isn't behaving as expected:
- `browser_get_console_logs()` — check for JS errors
- `browser_get_network_logs()` — check for failed API calls or unexpected redirects
- `browser_screenshot()` — see the visual state

## What the User Sees

The user watches the browser live. They see every navigation and interaction as it happens. This means:
- Narrate significant steps in your chat response so they understand what you're doing
- Don't interact faster than they can follow if the task is sensitive
- When handing off, explain clearly what you've done and what you need them to do
