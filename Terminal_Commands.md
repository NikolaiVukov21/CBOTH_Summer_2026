# Read Me
The commands in this guide cover the standard workflow for cloning, updating, and contributing to this repository. 


## First Time Usage:
> [!IMPORTANT]
>This should be done only once. Once the folder is created, the following command is no longer needed.

- To clone the repository: <br> 
```git clone https://github.com/NikolaiVukov21/CBOTH_Summer_2026.git```

## Before Coding:

- connecting to file in the future: <br>
```cd CBOTH_Summer_2026```

### Checking and updating file
- Checking for updates/ changes: <br>
```git status```

- Updating local file: <br>
```git pull origin main```

### Creating new branches
- Creating a new branch for staging pull requests: <br>
```git checkout -b branch-name```

> [!IMPORTANT]
> Make sure you are on the new branch for commits and changes
>- Checking current branch
```git branch --show-current```

## After Coding:

### Staging Commits
> [!WARNING]
>Always make sure to check that your local file is up to date with the repository <br>
>- ```git status``` <br>
>- ```git pull origin main``` <br>

- Staging commits: <br>
```git add .```

### Commenting and Pushing Request
- To save the changes and leave a message <br>
```git commit -m "Describe the changes made"```

- Pushing the commit to the branch (Pull Request)<br>
```git push origin branch-name```

- Switching Branches: <br>
```git switch <branch name>```
