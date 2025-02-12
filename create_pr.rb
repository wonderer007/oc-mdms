#!/usr/bin/env ruby

require 'open3'
require 'pathname'

# Get current branch name
branch_name = `git symbolic-ref --short HEAD`.strip
branch_regex = /^([a-zA-Z]*\/)?[a-zA-Z]{2,3}-[0-9]+/
branch_prefix = branch_name.match(branch_regex)&.[](0)
jira_ticket = branch_name.match(/(?i)[a-zA-Z]{2,3}-[0-9]+/)&.[](0)
repo_name = Pathname.pwd.basename.to_s
target_branches = ["main", "ci-devel-server", "ci-stage-server"]

if jira_ticket
  # Format ticket title from branch name
  ticket_title = branch_name[branch_prefix.length..]
    .gsub(/[-_]/, ' ')
    .split
    .map(&:capitalize)
    .join(' ')

  commit_message = `git log -1 --pretty=%B`.strip
  jira_link = "https://owenscorning.atlassian.net/browse/#{jira_ticket}"

  pr_urls = []
  pr_branches = []

  # Create PRs for each target branch
  target_branches.each do |base_branch|
    pr_title = "[#{base_branch}, #{repo_name}] #{jira_ticket}: #{ticket_title}"
    pr_description = "JIRA: #{jira_link}\n\n## Describe your changes\n#{commit_message}"
    
    pr_url = `gh pr create --title "#{pr_title}" --body "#{pr_description}" --head "#{branch_name}" --base "#{base_branch}"`.strip
    pr_urls << pr_url
    pr_branches << base_branch
    puts "Pull request created for #{base_branch}!"
  end

  # Update PR descriptions with cross-references
  pr_branches.each_with_index do |base_branch, i|
    new_description = "JIRA: #{jira_link}\n\n"
    
    pr_branches.each_with_index do |other_branch, j|
      if other_branch != base_branch
        new_description += "\nPR against `#{other_branch}`: #{pr_urls[j]}\n"
      end
    end
    
    new_description += "\n## Describe your changes\n#{commit_message}"
    
    system("gh", "pr", "edit", pr_urls[i], "--body", new_description)
    puts "Updated description for PR against #{base_branch}"
  end

  puts "All pull requests created and updated successfully!"
else
  puts "Can not find JIRA ticket number"
end 