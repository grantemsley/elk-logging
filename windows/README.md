# Configuring Windows Auditing

## Group Policy
Create a group policy for auditing, and configure with the audit policies shown in the screenshots in the grouppolicy folder.

## SACL Entries

To actually audit some changes in active directory, you need to create SACL entries to tell AD to create the audit logs.

Open AD Users and Computers, turn on show advanced features, right click and select properties for the top of the domain (or for specific OUs, if that's all you are interested in).
Go to the Security tab, click Advanced. Go to Auditing tab. Click Add.

Select Everyone as the principal, type success, and applies to this object and all descendant objects. Then at the very bottom click clear all to remove the defaults, and check:

- Delete
- Delete subtree
- Modify owner
- Create Computer objects
- Delete Computer objects
- Create Contact objects
- Delete Contact objects
- Create Group objects
- Delete Group objects
- Create groupPolicyContainer objects
- Delete groupPolicyContainer objects
- Create Organizational Unit objects
- Delete Organizational Unit objects
- Create User objects
- Delete User objects
