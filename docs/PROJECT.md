
```
# 1. Create a new ASP.NET Core web app boilerplate
dotnet new webapp -n MyAspNetApp

# 2. Change into the project directory
cd MyAspNetApp

# 3. Modify the .csproj to target .NET Framework 4.7.2 instead of modern .NET
(Get-Content MyAspNetApp.csproj) -replace '<TargetFramework>net.*</TargetFramework>', '<TargetFramework>net472</TargetFramework>' | Set-Content MyAspNetApp.csproj
```

