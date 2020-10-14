$GithubAPIBaseURI = "https://api.github.com/repos"

function Get-GitHubHeaders ($token) {
  $headers = @{
    Authorization = "bearer $token"
  }
  return $headers
}

function Invoke-GitHubAPIPost {
  param (
    [Parameter(Mandatory = $true)]
    $apiURI,
    [Parameter(Mandatory = $true)]
    $body,
    [Parameter(Mandatory = $true)]
    $token
  )

  $resp = Invoke-RestMethod `
    -Method POST `
    -Body ($body | ConvertTo-Json) `
    -Uri $apiURI `
    -Headers (Get-GitHubHeaders -token $token) `
    -MaximumRetryCount 3

  return $resp
}

function Invoke-GitHubAPIPatch {
  param (
    [Parameter(Mandatory = $true)]
    $apiURI,
    [Parameter(Mandatory = $true)]
    $body,
    [Parameter(Mandatory = $true)]
    $token
  )

  $resp = Invoke-RestMethod `
    -Method PATCH `
    -Body ($body | ConvertTo-Json) `
    -Uri $apiURI `
    -Headers (Get-GitHubHeaders -token $token) `
    -MaximumRetryCount 3

  return $resp
}

function Invoke-GitHubAPIDelete {
  param (
    [Parameter(Mandatory = $true)]
    $apiURI,
    [Parameter(Mandatory = $true)]
    $token
  )

  $resp = Invoke-RestMethod `
    -Method DELETE `
    -Uri $apiURI `
    -Headers (Get-GitHubHeaders -token $token) `
    -MaximumRetryCount 3

  return $resp
}


function Invoke-GitHubAPIGet {
  param (
    [Parameter(Mandatory = $true)]
    $apiURI,
    $token
  )

  if ($token)
  {
    $resp = Invoke-RestMethod `
      -Method GET `
      -Uri $apiURI `
      -Headers (Get-GitHubHeaders -token $token) `
      -MaximumRetryCount 3
  }
  else {
    $resp = Invoke-RestMethod `
      -Method GET `
      -Uri $apiURI `
      -MaximumRetryCount 3
  }

  return $resp
}

function Split-Members ($membersString)
{
  if (!$membersString) { return $null }
  return @($membersString.Split(",") | % { $_.Trim() } | ? { return $_ })
}

function Set-BodyParameters ($members,  $parameterName, $parameters, $allowEmptyMembers=$false)
{
  if ($members) { 
    if ($members -is [array])
    {
      $parameters[$parameterName] = @($members)
    }
    elseif (![System.String]::IsNullOrWhiteSpace($members) -or $allowEmptyMembers) {
      $memberAdditions = Split-Members -membersString $members
      $parameters[$parameterName] = @($memberAdditions)
    }
  }

  return $parameters
}

function List-PullRequests {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [ValidateSet("open","closed","all")]
    $State = "open",
    $Head,
    $Base,
    [ValidateSet("created","updated","popularity","long-running")]
    $Sort,
    [ValidateSet("asc","desc")]
    $Direction,
    [Parameter(DontShow)]
    $PullRequestNumber
  )

  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/pulls"
  if ($State -or $Head -or $Base -or $Sort -or $Direction) { 
    $uri += '?'
  }
  elseif ($PullRequestNumber) {
    $uri += "/${PullRequestNumber}"
  }
  if ($State) { $uri += "state=$State&" }
  if ($Head) { $uri += "head=$Head&" }
  if ($Base) { $uri += "base=$Base&" }
  if ($Sort) { $uri += "sort=$Sort&" }
  if ($Direction){ $uri += "direction=$Direction&" }

  return Invoke-GitHubAPIGet -apiURI $uri
}

# 
<#
.PARAMETER Ref
Ref to search for
Pass 'heads/<branchame> ,tags/<tag name>, or nothing
#>
function List-References {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    $Ref
  )

  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/git/matching-refs/"
  if ($Ref) { $uri += "$Ref" }

  return Invoke-GitHubAPIGet -apiURI $uri
}

function Get-PullRequest {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [Parameter(Mandatory = $true)]
    $PullRequestNumber
  )

  return List-PullRequests -RepoOwner $RepoOwner -RepoName $RepoName -PullRequestNumber $PullRequestNumber
}

function Create-PullRequest {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [Parameter(Mandatory = $true)]
    $Title,
    [Parameter(Mandatory = $true)]
    $Head,
    [Parameter(Mandatory = $true)]
    $Base,
    $Body=$Title,
    [Boolean]$Maintainer_Can_Modify=$false,
    [Boolean]$Draft=$false,
    [Parameter(Mandatory = $true)]
    $AuthToken
  )

  $parameters = @{
    title                 = $Title
    head                  = $Head
    base                  = $Base
    body                  = $Body
    maintainer_can_modify = $Maintainer_Can_Modify
    $draft                = $Draft
  }

  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/pulls"
  return Invoke-GitHubAPIPost -apiURI $uri -body $parameters -token $AuthToken
}

function Add-IssueComment {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [Parameter(Mandatory = $true)]
    $IssueNumber,
    [Parameter(Mandatory = $true)]
    $Comment,
    [Parameter(Mandatory = $true)]
    $AuthToken

  )
  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/issues/$IssueNumber/comments"

  $parameters = @{
    body = $Comment
  }

  return Invoke-GitHubAPIPost -apiURI $uri -body $parameters -token $AuthToken
}

# Will add labels to existing labels on the issue
function Add-IssueLabels {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [Parameter(Mandatory = $true)]
    $IssueNumber,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $true)]
    $Labels,
    [Parameter(Mandatory = $true)]
    $AuthToken
  )

  if ($Labels.Trim().Length -eq 0)
  {
    throw "The 'Labels' parameter should not not be whitespace..`
    You can use the 'Update-Issue' function if you plan to reset the labels"
  }

  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/issues/$IssueNumber/labels"
  $labelAdditions = Split-Members -membersString $Labels
  $parameters = @{
    labels = @($labelAdditions)
  }

  return Invoke-GitHubAPIPost -apiURI $uri -body $parameters -token $AuthToken
}

# Will add assignees to existing assignees on the issue
function Add-IssueAssignees {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [Parameter(Mandatory = $true)]
    $IssueNumber,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $true)]
    $Assignees,
    [Parameter(Mandatory = $true)]
    $AuthToken
  )

  if ($Assignees.Trim().Length -eq 0)
  {
    throw "The 'Assignees' parameter should not be whitespace.`
    You can use the 'Update-Issue' function if you plan to reset the Assignees"
  }

  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/issues/$IssueNumber/assignees"
  $assigneesAdditions = Split-Members -membersString $Assignees
  $parameters = @{
    assignees = @($assigneesAdditions)
  }

  return Invoke-GitHubAPIPost -apiURI $uri -body $parameters -token $AuthToken
}

function Request-PrReviewer {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [Parameter(Mandatory = $true)]
    $PrNumber,
    [ValidateNotNullOrEmpty()]
    $Users,
    [ValidateNotNullOrEmpty()]
    $Teams,
    [Parameter(Mandatory = $true)]
    $AuthToken
  )

  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/pulls/$PrNumber/requested_reviewers"
  $parameters = @{}
  $parameters = Set-BodyParameters -members $Users -parameterName "reviewers"` -parameters $parameters
  $parameters = Set-BodyParameters -members $Users -parameterName "team_reviewers" -parameters $parameters

  if ($parameters.Count -gt 0) {
    return Invoke-GitHubAPIPost -apiURI $uri -body $parameters -token AuthToken
  }
  else {
    throw "Did not fire request because of empty body."
  }
}

# For labels and assignee pass comma delimited string, to replace existing labels or assignees.
# Or pass white space " " to remove all labels or assignees
function Update-Issue {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [Parameter(Mandatory = $true)]
    $IssueNumber,
    [string]$Title,
    [string]$Body,
    [ValidateSet("open","closed")]
    [string]$State,
    [int]$Milestome,
    [ValidateNotNullOrEmpty()]
    $Labels,
    [ValidateNotNullOrEmpty()]
    $Assignees,
    [Parameter(Mandatory = $true)]
    $AuthToken
  )

  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/issues/$IssueNumber"
  $parameters = @{}
  if ($Title) { $parameters["title"] = $Title }
  if ($Body) { $parameters["body"] = $Body }
  if ($State) { $parameters["state"] = $State }
  if ($Milestone) { $parameters["milestone"] = $Milestone }

  $parameters = Set-BodyParameters -members $Labels -parameterName "labels"`
   -parameters $parameters -allowEmptyMembers $true
  $parameters = Set-BodyParameters -members $Assignees -parameterName "assignees"`
   -parameters $parameters -allowEmptyMembers $true

  if ($parameters.Count -gt 0) {
    return Invoke-GitHubAPIPatch -apiURI $uri -body $parameters -token $AuthToken
  }
  else {
    throw "Did not fire request because of empty body."
  }
}

function Delete-References {
  param (
    [Parameter(Mandatory = $true)]
    $RepoOwner,
    [Parameter(Mandatory = $true)]
    $RepoName,
    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory = $true)]
    $Ref,
    [Parameter(Mandatory = $true)]
    $AuthToken
  )

  if ($Ref.Trim().Length -eq 0)
  {
    throw "You must supply a valid 'Ref' Parameter to 'Delete-Reference'."
  }

  $uri = "$GithubAPIBaseURI/$RepoOwner/$RepoName/git/refs/$Ref"

  return Invoke-GitHubAPIDelete -apiURI $uri -token $AuthToken
}