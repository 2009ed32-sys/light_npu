# Git Commands For This PC

This repository is stored at:

```powershell
C:\Users\2009e\npusources
```

The GitHub remote is:

```text
https://github.com/2009ed32-sys/light_npu.git
```

On this PC, `git` is not currently available from the normal `PATH`.
Use the Visual Studio bundled Git executable:

```powershell
$git = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe"
```

## Basic Workflow

Go to the repository:

```powershell
cd C:\Users\2009e\npusources
```

Check current status:

```powershell
& $git status -sb
```

See changed files:

```powershell
& $git diff --name-only
```

See detailed changes:

```powershell
& $git diff
```

Stage selected files:

```powershell
& $git add apb_top/convcore.sv apb_top/cmac.sv mainc/main.c
```

Stage all non-ignored changes:

```powershell
& $git add .
```

Commit:

```powershell
& $git commit -m "Describe the change"
```

Push to GitHub:

```powershell
& $git push
```

## Common Checks

Show the remote:

```powershell
& $git remote -v
```

Show the latest commit:

```powershell
& $git log --oneline -1
```

Show recent commits:

```powershell
& $git log --oneline --decorate -10
```

Check ignored files:

```powershell
& $git status --ignored -sb
```

## First Push Already Done

The initial push was already completed:

```text
branch: main
remote: origin/main
commit: 2da9f84 Initial light NPU sources
```

So future work usually only needs:

```powershell
cd C:\Users\2009e\npusources
$git = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe"
& $git status -sb
& $git add .
& $git commit -m "Describe the change"
& $git push
```

## Recommended Source Scope

Use `C:\Users\2009e\npusources` as the source-of-truth repository.

Good files to commit:

```text
apb_top/
apb_debug/
axi_master/
axi_top/
convcore/
csb/
mainc/
tb/
*.md
```

Do not commit generated Vivado/XSim files. They are ignored by `.gitignore`, including:

```text
.Xil/
.xsim*/
xsim.dir/
*.log
*.jou
*.pb
*.wdb
*.vcd
```

## If Push Fails

If Git asks for GitHub authentication, sign in with the browser prompt or Git Credential Manager prompt.

If `git` is later added to `PATH`, the short form works too:

```powershell
git status -sb
git add .
git commit -m "Describe the change"
git push
```
