# asp_modernization

A report of using Claude code to convert legacy ASP.NET to modern Java/Angular using Claude AI.


## Introduction
This repository is the report of an intertive process to investigate using Claude code to convert ASP.NET Framework 4.7.2, C#, MVC or WebForms projects into Java 21/Spring Boot 8.0. In an attempt to be empiracle, this take a systematic approach decomposing an ASP.NET WebForms project into its different parts, then systematically converting and testing the results. It begins with an exeplar web forms project created by Visual Studio 2017, then add all the additional components an enterpries ASP.NET project may use. 
The asp project is contained in [aspnet-webforms](https://github.com/davidharrisnet/aspnetwebforms).  The full report in [RESEARCH.md](docs/RESEARCH.md) has the following format:

## Prerequisites

1. .NET Frameworks 4.7.2.  
Open [.NET Framework 4.7.2](https://support.microsoft.com/en-us/servicing/os/windows/2019/07/microsoft-net-framework-4-7-2-offline-installer-for-windows), then select "Download the Microsoft .NET Framework 4.7.2 offline installer package now."

3. Install Visual Studio 2017
* [Visual Studio 2017 via microsoft.com](https://download.visualstudio.microsoft.com/download/pr/8729ca3d-c3b2-4b32-b6fb-a7ea468a4af2/4448a86b1ae7d5b90bdc9c51e3f18b8f6ab0d3176560aa23b03f102380e02746/vs_Community.exe)

  * Using the Visual Studio Installer, select Modify, the select ASP.NET and web development
  * Add a selection to .NET Framework 4.7.2 development tools
    
### ASP.NET Projects
So this is a repeatable process, I chose to create two of Visual Studio's default ASP projects
#### ASP.NET WEb Forms Site
1. File | New | Project | ASP.NET Web Forms Site
2. Ensure Framework is .NET Framework 4.7.2
3. This project has several components
   * aspx file: Default, Contact, About, Global
   * bootstrap style sheets
   * An Account directory with Login pages and security policies specified in the Web.config.\
   * Routing in App_Code/RouteConfig.cs
#### ASP.NET Web Site (Razor v3)

## Analysis 





 



 
