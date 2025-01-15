Deletion of Former Employees' User Profiles
Overview
This PowerShell script is a tool designed to streamline the management of local user profiles on network computers by automatically identifying and deleting profiles associated with former employees. It ensures a clean and secure environment while optimizing disk space usage and minimizing manual administrative effort.

Features
🔍 Identify Former Employees
Retrieves a list of former employees by filtering disabled accounts in Active Directory.
Uses SamAccountName for precise matching with local profiles.
🌐 Scan Active Computers
Detects computers within specified organizational units (OUs) in Active Directory.
Filters out offline computers, ensuring the script only interacts with available systems.
🗂 Match and Delete Local Profiles
Scans the C:\Users directory on each computer for folders matching the SamAccountName of former employees.
Deletes folders with confirmed matches, freeing up disk space and maintaining security.
📋 Detailed Logging
Provides comprehensive terminal output to track every step of the process:
Profiles found on each computer.
Matches between local folders and former employee accounts.
Status of folder deletions (success or failure).
Why Use This Script?
Automated Cleanup: Automatically removes outdated user profiles, saving hours of manual work.
Enhanced Security: Reduces the risk of unauthorized access to sensitive data left in old user profiles.
Disk Space Optimization: Frees up valuable disk space on workstations and servers.
Administrative Simplicity: Handles profile management across multiple computers with ease.
How It Works
Retrieve Data: Gathers information about disabled user accounts from Active Directory.
Match Profiles: Compares the SamAccountName of former employees with folder names in C:\Users.
Perform Actions: Deletes matched folders and logs the results for each action.
Usage
Prerequisites:

Ensure the script runs with administrative privileges.
Active Directory PowerShell module must be installed.
Setup:

Specify the target OUs in the script.
Provide the necessary credentials when prompted.
Execution:
Run the script in a PowerShell environment:

powershell
Копировать код
.\DeleteFormerEmployeeProfiles.ps1
Example Output
plaintext
Копировать код
Fetching the list of former employees...  
Found 25 disabled accounts.  
Scanning computers in region: OU=Computers,OU=Departments,DC=corp,DC=example,DC=com  
Found 50 computers.  
Checking computer: WSHP123  
- Found folder: john.doe  
  Match found with former employee account: john.doe  
  Deleting folder...  
  Folder deleted successfully!  

Scanning complete. Total folders deleted: 10  
Contribution
Feel free to contribute to this project by opening issues or submitting pull requests. Together, we can make this tool even more robust!

License
This script is distributed under the MIT License. See LICENSE for details.

Enjoy automated profile management and keep your systems clean! 😊
