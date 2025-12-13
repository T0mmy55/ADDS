# ADDS
Repository for ADDS scripts

# SYNOPSIS
    Lists AD users with their effective password settings AND all applicable PSOs
    (directly linked or via groups), including each PSO's Precedence.
    
# Execution and results

[+] Getting applied password policies on all active directory users with effective PSO precedence

<img width="1457" height="712" alt="image" src="https://github.com/user-attachments/assets/e936b461-e3f5-4bcb-8187-38ac8953d2bc" />
<img width="1376" height="377" alt="image" src="https://github.com/user-attachments/assets/4d567d04-08f7-4635-89e0-d5990aed9ffc" />

[+] Getting applied password policies on specific OU [Distinguished name]; export all the extracted users and PSO information to a csv file

<img width="1677" height="51" alt="image" src="https://github.com/user-attachments/assets/6b0b9607-6889-4158-8d55-e1acb9a4d630" />

- All users file export : Users_PSO_Expanded_All.csv
- .\Get-AdUsers-AllPSO-WithPrecedence.ps1 -ExpandPerPSO -OutCsv .\Users_PSO_Expanded_All.csv
<img width="1862" height="645" alt="image" src="https://github.com/user-attachments/assets/9e69500f-b853-45e2-b686-820659c0e8c2" />

- Effective applied PSO on user T0-Othmane [Duplicate found]
<img width="1693" height="126" alt="image" src="https://github.com/user-attachments/assets/2f046967-bf8c-4ea5-b6aa-c74b73e9dfe6" />

- Target a specific OU then export to a CSV file : Users_PSO_Expanded_Tier2.csv
- .\Get-AdUsers-AllPSO-WithPrecedence.ps1 -UseTokenGroups -EnabledOnly -SearchBase "OU=Users,OU=Tier 2,OU=0_Tier Model Administration,DC=contoso,DC=com"
<img width="1868" height="180" alt="image" src="https://github.com/user-attachments/assets/4f6cc522-b94e-491d-bd5a-8c17920126eb" />







