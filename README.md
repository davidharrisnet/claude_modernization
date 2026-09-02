# asp_modernization

A report of using Claude code to convert legacy ASP.NET to modern Java/Angular using Claude AI.

The full report in [RESEARCH.md](docs/RESEARCH.md) has the following format:

## Prerequisites

It may be possible to develop in .NET 4.7.2 in a modern Visual Studio IDE, but I was not successful. Rather, I decided to use a Windows 10 machine, and install only the essential components. 

1. Using the Visual Studio Installer, I removed all currently installed Visual Studio versions, and using the App & features tool, removed all .NET Frameworks 
2. .NET Frameworks 4.7.2.  
Install [.NET Framework 4.7.2](https://support.microsoft.com/en-us/servicing/os/windows/2019/07/microsoft-net-framework-4-7-2-offline-installer-for-windows)
3. Install Visual Studio 2017
* From [Redit](https://www.reddit.com/r/VisualStudio/comments/1all0d4/is_visual_studio_2017_community_version_still/)
[Visual Studio 2017 via web.archive.org](https://web.archive.org/web/20240308034322/https://download.visualstudio.microsoft.com/download/pr/119c57b9-af7b-4970-81ff-824299902e62/46731b262625013cb400e2feb083b088f4139158f9a8166feff471e6806dc20d/vs_Community.exe)

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


## Reports
### ASP.NET C# Web Forms 
### ASP.NET C# MVC



 



 
