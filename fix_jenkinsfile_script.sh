#!/bin/bash

# Script to fix missing --custom-platform=linux/arm64 in Jenkinsfiles across repositories
# Requirements: gh CLI tool installed and authenticated

set -e

# Configuration
GITHUB_ORG="SimonStiil"
BRANCH_NAME="fix-kaniko-platform"
COMMIT_MESSAGE="Fix missing --custom-platform=linux/arm64 in Jenkinsfile"
PR_TITLE="Fix missing --custom-platform=linux/arm64 in Jenkinsfile"
PR_BODY="This PR fixes the missing --custom-platform=linux/arm64 flag in the /kaniko/executor command in Jenkinsfile."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if gh CLI is installed and authenticated
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed. Please install it first."
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        print_error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    
    print_status "Prerequisites check passed."
}

# Function to get all repositories for the organization
get_repositories() {
    print_status "Fetching repositories for organization: $GITHUB_ORG"
    gh repo list "$GITHUB_ORG" --limit 100 --json name,sshUrl | jq -r '.[] | .name'
}

# Function to check if repository has Jenkinsfile
has_jenkinsfile() {
    local repo_name=$1
    gh api "repos/$GITHUB_ORG/$repo_name/contents/Jenkinsfile" &> /dev/null
}

# Function to check if Jenkinsfile needs fixing
needs_fixing() {
    local jenkinsfile_content=$1
    
    # Check if it contains kaniko executor line but missing --custom-platform=linux/arm64
    if echo "$jenkinsfile_content" | grep -q "/kaniko/executor.*--force.*--context.*--destination" && \
       ! echo "$jenkinsfile_content" | grep -q "/kaniko/executor.*--custom-platform=linux/arm64"; then
        return 0
    fi
    return 1
}

# Function to fix the Jenkinsfile content
fix_jenkinsfile() {
    local jenkinsfile_content=$1
    
    # Use sed to add --custom-platform=linux/arm64 after --log-format text
    echo "$jenkinsfile_content" | sed 's|/kaniko/executor --force --context `pwd` --log-format text --destination|/kaniko/executor --force --context `pwd` --log-format text --custom-platform=linux/arm64 --destination|g'
}

# Function to process a single repository
process_repository() {
    local repo_name=$1
    local temp_dir="/tmp/fix_jenkinsfile_${repo_name}"
    
    print_status "Processing repository: $repo_name"
    
    # Check if repository has Jenkinsfile
    if ! has_jenkinsfile "$repo_name"; then
        print_warning "Repository $repo_name does not have a Jenkinsfile. Skipping."
        return 0
    fi
    
    # Get current Jenkinsfile content
    local jenkinsfile_content
    jenkinsfile_content=$(gh api "repos/$GITHUB_ORG/$repo_name/contents/Jenkinsfile" --jq '.content' | base64 -d)
    
    # Check if it needs fixing
    if ! needs_fixing "$jenkinsfile_content"; then
        print_warning "Repository $repo_name: Jenkinsfile doesn't need fixing. Skipping."
        return 0
    fi
    
    print_status "Repository $repo_name: Jenkinsfile needs fixing. Processing..."
    
    # Clone the repository
    rm -rf "$temp_dir"
    git clone "https://github.com/$GITHUB_ORG/$repo_name.git" "$temp_dir"
    cd "$temp_dir"
    
    # Create a new branch
    git checkout -b "$BRANCH_NAME"
    
    # Fix the Jenkinsfile
    local fixed_content
    fixed_content=$(fix_jenkinsfile "$jenkinsfile_content")
    echo "$fixed_content" > Jenkinsfile
    
    # Check if there are actual changes
    if ! git diff --quiet; then
        # Commit the changes
        git add Jenkinsfile
        git commit -m "$COMMIT_MESSAGE"
        
        # Push the branch
        git push origin "$BRANCH_NAME"
        
        # Create a pull request
        gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base main --head "$BRANCH_NAME"
        
        print_status "Repository $repo_name: Pull request created successfully."
    else
        print_warning "Repository $repo_name: No changes detected after processing."
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$temp_dir"
}

# Function to process all repositories
process_all_repositories() {
    local repositories
    repositories=$(get_repositories)
    
    local total_repos=0
    local processed_repos=0
    
    while IFS= read -r repo_name; do
        if [ -n "$repo_name" ]; then
            total_repos=$((total_repos + 1))
            if process_repository "$repo_name"; then
                processed_repos=$((processed_repos + 1))
            fi
        fi
    done <<< "$repositories"
    
    print_status "Processing complete. Processed $processed_repos out of $total_repos repositories."
}

# Function to run in dry-run mode
dry_run() {
    print_status "Running in dry-run mode..."
    
    local repositories
    repositories=$(get_repositories)
    
    local repos_with_jenkinsfile=0
    local repos_needing_fix=0
    
    while IFS= read -r repo_name; do
        if [ -n "$repo_name" ]; then
            if has_jenkinsfile "$repo_name"; then
                repos_with_jenkinsfile=$((repos_with_jenkinsfile + 1))
                
                local jenkinsfile_content
                jenkinsfile_content=$(gh api "repos/$GITHUB_ORG/$repo_name/contents/Jenkinsfile" --jq '.content' | base64 -d)
                
                if needs_fixing "$jenkinsfile_content"; then
                    repos_needing_fix=$((repos_needing_fix + 1))
                    print_status "Repository $repo_name: NEEDS FIXING"
                else
                    print_status "Repository $repo_name: OK"
                fi
            fi
        fi
    done <<< "$repositories"
    
    print_status "Dry-run complete:"
    print_status "  - Repositories with Jenkinsfile: $repos_with_jenkinsfile"
    print_status "  - Repositories needing fix: $repos_needing_fix"
}

# Main function
main() {
    echo "GitHub Jenkinsfile Kaniko Platform Fix Script"
    echo "============================================="
    
    # Parse command line arguments
    local dry_run_mode=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run_mode=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--dry-run] [--help]"
                echo "  --dry-run    Show what would be changed without making changes"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    
    if [ "$dry_run_mode" = true ]; then
        dry_run
    else
        print_warning "This script will create branches and pull requests in your repositories."
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            process_all_repositories
        else
            print_status "Operation cancelled by user."
        fi
    fi
}

# Run the main function with all arguments
main "$@"