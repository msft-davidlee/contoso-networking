# Disclaimer
The information contained in this README.md file and any accompanying materials (including, but not limited to, scripts, sample codes, etc.) are provided "AS-IS" and "WITH ALL FAULTS." Any estimated pricing information is provided solely for demonstration purposes and does not represent final pricing and Microsoft assumes no liability arising from your use of the information. Microsoft makes NO GUARANTEES OR WARRANTIES OF ANY KIND, WHETHER EXPRESSED OR IMPLIED, in providing this information, including any pricing information.


# Introduction
This project is to help you setup internal networking for demo environments used in Contoso. Note that there will be 2 Virtual Networks (VNets) created per environment, one in a primary region, and one in a secondary region which can be leveraged in case there's a DR event. This project uses github actions to execute the deployment workflow. A Bicep file defines the resources to be created. 

There will also be two environments, one for development and one for production. This means at the end of the day, you will see 4 VNets. There will be peering between VNets of the same environment, but not between environments to ensure development or production traffic do NOT cross.

# Get Started
To create this networking environment in your Azure subscription, please follow the steps below.

1. Fork this git repo. See: https://docs.github.com/en/get-started/quickstart/fork-a-repo
2. Follow the steps in https://github.com/msft-davidlee/contoso-governance to create the necessary resources via Azure Blueprint.
3. Run UpdateConfig.ps1 which will configure your source IP address. This will configure network access to http/https services from your office/home IP.
4. Create the following secret(s) in your github per environment. Be sure to populate with your desired values. The values below are all suggestions.

## Picking Regions
Consider which is your primary and DR region. Any primary region should be paired with a DR region that is documented as a paired region: https://docs.microsoft.com/en-us/azure/best-practices-availability-paired-regions. The regions are hardcoded in the app.yml file which you can edit and modify.

## Secrets
| Name | Value |
| --- | --- |
| MS_AZURE_CREDENTIALS | <pre>{<br/>&nbsp;&nbsp;&nbsp;&nbsp;"clientId": "",<br/>&nbsp;&nbsp;&nbsp;&nbsp;"clientSecret": "", <br/>&nbsp;&nbsp;&nbsp;&nbsp;"subscriptionId": "",<br/>&nbsp;&nbsp;&nbsp;&nbsp;"tenantId": "" <br/>}</pre> |