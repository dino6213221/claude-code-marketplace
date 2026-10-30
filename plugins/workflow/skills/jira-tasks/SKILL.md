---
name: jira-tasks
description: Turn user intents, meeting notes or bug reports into clear, actionable Jira tasks using Story and Bug templates, title conventions and field guidance. Use when creating, drafting or refining a Jira issue, story, bug or sub-task.
---

# Creating Jira Tasks

As an AI Agent, your role is to transform user intents, meeting notes, or bug reports into professional, clear, and actionable Jira tasks.

Your goal is to minimize ambiguity and ensure that the developer or assignee has all the necessary information to start working.

## 1. Golden Rules for Task Creation

* **Be precise and concise:** Avoid fluff. Use bullet points and bold text to highlight key information.

* **Do not guess:** If the user's request is too vague and lacks key information (e.g., what should happen in case of an error), **ask the user clarifying questions before creating the task**.

* **Markdown formatting:** Always use Markdown formatting in the issue description to ensure a readable structure.

* **One problem = one task:** If the user provides multiple unrelated changes, suggest splitting them into separate issues (e.g., separate Stories or Sub-tasks).

## 2. Summary (Title) Format

The title must be understandable without reading the description.

* **Rule:** `[Type] Short, concise description of the action (Verb + Noun)`

* **GOOD Examples:**

    * `[FEATURE] Add Google Login to the registration screen`

    * `[BUG] "Buy Now" button is unresponsive on mobile devices (iOS)`

    * `[CHORE] Update React library to version 18`

* **BAD Examples:**

    * `Login` (too general)

    * `Error on the main page, nothing works` (lack of specifics)

## 3. Task Templates

Depending on the issue type, ALWAYS use one of the following templates in the "Description" field.

### Template A: New Feature (Story / Feature)

Use this template for new features that deliver business value.

```
**Context / Business Value:**
As a [type of user, e.g., logged-in customer],
I want to [perform an action, e.g., download a PDF invoice],
so that I can [achieve a goal/benefit, e.g., settle accounts with accounting].

**Acceptance Criteria:**
*Use BDD format (Given/When/Then) or clear bullet points.*
1. **Scenario 1: [Scenario Name]**
   * **Given** [initial condition]
   * **When** [user action]
   * **Then** [expected result]
2. [Next criterion, e.g., The button must be visible only for "Admin" roles]

**Technical Details / Notes (Optional):**
*   [e.g., Link to API documentation]
*   [e.g., Performance constraints]

**Design Assets:**
*   [Place for Figma/Miro link]

```

### Template B: Bug

Use this template when something is not working as expected.

```
**Bug Description:**
[Short summary, e.g., Users receive a 500 error when trying to change their password.]

**Steps to reproduce:**
1. Log in to a test account.
2. Go to the "Account Settings" tab.
3. Enter a new password and click "Save".
4. Observe the error.

**Expected result:**
[e.g., The password is changed successfully, and the user sees a green success message.]

**Actual result:**
[e.g., The page loads for 10 seconds and then returns a "500 Error" screen.]

**Environment:**
*   **Platform/Browser:** [e.g., Chrome 114, iOS Safari]
*   **Environment:** [e.g., Production, Staging]

```

## 4. Metadata Management (Jira Fields)

When creating a task via API or suggesting its creation, pay attention to the following fields (if data is available):

* **Issue Type:** Epic, Story, Task, Sub-task, or Bug.

* **Priority:**

    * `Highest` (Production outage, work blocker).

    * `High` (Important business feature).

    * `Medium` (Standard priority - Default).

    * `Low` (Minor tweaks, typos).

* **Labels:** Suggest concise tags to facilitate filtering (e.g., `frontend`, `backend`, `payment`, `ui`).

## 5. Agent Workflow

1. **Analysis:** Analyze the user's text.

2. **Gap Verification:** Do you know WHO the actor is? WHAT needs to be done? WHY? What is the goal?

3. **Questions (if needed):** If Acceptance Criteria or steps to reproduce a bug are missing, ask the user to provide them.

4. **Generation:** Generate a task preview using the appropriate template (Story or Bug).

5. **Confirmation:** Ask the user to approve the content before finally creating the issue in the system.
