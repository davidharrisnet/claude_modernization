# asp_modernization

A report of using Claude code to convert legacy ASP.NET to modern Java/Angular using Claude AI.


## Introduction
This repository is the report of an intertive process to investigate using Claude code to convert ASP.NET Framework 4.7.2, C#, MVC or WebForms projects into Java 21/Spring Boot 8.0. In an attempt to be empiracle, this take a systematic approach decomposing an ASP.NET WebForms project into its different parts, then systematically converting and testing the results. It begins with an exeplar web forms project created by Visual Studio 2017, then add all the additional components an enterpries ASP.NET project may use. The asp web forms project is contained in [aspnet-webforms](https://github.com/davidharrisnet/aspnetwebforms) The full report in [RESEARCH.md](docs/RESEARCH.md) has the following format:

## Prerequisites

1. .NET Frameworks 4.7.2.  
Open [.NET Framework 4.7.2](https://support.microsoft.com/en-us/servicing/os/windows/2019/07/microsoft-net-framework-4-7-2-offline-installer-for-windows), then select "Download the Microsoft .NET Framework 4.7.2 offline installer package now."

3. Install Visual Studio 2017
* [Visual Studio 2017 via microsoft.com](https://download.visualstudio.microsoft.com/download/pr/8729ca3d-c3b2-4b32-b6fb-a7ea468a4af2/4448a86b1ae7d5b90bdc9c51e3f18b8f6ab0d3176560aa23b03f102380e02746/vs_Community.exe)

  * Using the Visual Studio Installer, select Modify, the select ASP.NET and web development
  * Add a selection to .NET Framework 4.7.2 development tools
    
### ASP.NET Projects

#### ASP.NET WEb Forms Site

1. File | New | Project | ASP.NET Web Forms Site
2. Ensure Framework is .NET Framework 4.7.2
3. This project has several components
   * aspx file: Default, Contact, About, Global
   * bootstrap style sheets
   * An Account directory with Login pages and security policies specified in the Web.config.\
   * Routing in App_Code/RouteConfig.cs
#### ASP.NET Web Site (Razor v3)
 ...
## Design
1. Given the exemplar web forms project, systematically test each component as listed in [ASP.md](https://github.com/davidharrisnet/aspnetwebforms/blob/asp_analysis/ASP.md).
2. Prompt Claude to convert the component the Java/Spring Boot with a regression test confirming its functionality.
3. Bring in the components in [Core Components](https://github.com/davidharrisnet/aspnetwebforms/blob/core_components/CORE_COMPONENTS.md)
4. Prompt Claude to convert the component the Java/Spring Boot with a regression test confirming its functionality.
5. Do not simply convert the projects, but build out a Java/Spring Boot regression suite to validate each component. This project can then be reused with claude to convert other projects. The Suite should test each component the produce a measurable report. 
6. With the regression suite established, bring in random ASP.NET 4.7.2 Frameworks from github
## Furthe Work
Random Samples
* https://github.com/PavlosTzitzos/asp.net-samples
* https://github.com/f2calv/WebAppDI
* https://github.com/search?q=asp.net+4.7.2&type=repositories





 



 
