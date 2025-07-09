Consolidate the 3 tabs in the "workspaces" settings GUI (workspaces, monitor assignments, and connected monitors) into 1 RESPONSIVE view. the monitor arrangement must be responsive and if it cant be showed in its entirety, then collapse it

Monitor assignments can be a column in the workspace config table

Create a new "parent container" for multiple workspace configurations. The scenario here is a user that has multiple desks/docking station setups. They should be able to configure all of those. Call this "parent container" a "workspace", thus the existing table is a given workspace's config. Allow the user to set friendly/custom display names. Provide helpful hints to the user to explain how this all works. Provide the example scenario of a user having multiple desks, each with a docking station and multiple monitors.

---

Review the entire settings GUI. It has very poor use of white space (way too much whitespace). Ensure all the necessary toggles are present and implemented. Fix the poor white space usage.

When the settings GUI opens, ensure it opens at the very top of the screen - z-index, it should be PRESENT to the user.


---

Add validations to the keybindings. If the user attempts to set a keybinding that conflicts with an existing global keybinding -- or the config currently conflicts with a global keybindings -- alert the user.

--- 

This project was forked from https://github.com/nikitabobko/AeroSpace at commit 2ccef29511696ab45dbe9bb5e05f772cf168483a. The project is/was licensed under the MIT license. Enforce a license that preserves as much IP rights as possible for me given this scenario.

----
Allow the user to configure a default workspace to open new windows in for a given app. 
