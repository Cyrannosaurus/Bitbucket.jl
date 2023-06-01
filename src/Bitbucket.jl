module Bitbucket

using HTTP, Base64, JSON, Dates, Base.Iterators

export User, AuthenticatedUser, Person, Repository, ReviewStatus, ParticipationType, PullRequest, PullRequestStatus

export Approved, UnApproved, NeedsWork
export Author, Reviewer, Participant, NotOnPR
export Open, Declind, Merged

export GetRepoPRs, GetUserPRs, GetRole, Authenticate

"""
A struct to represent the person running the queries.
# Fields
- username: A username as it appears in BitBucket
- token: An HTTP token or the user's password. Using a token is recommended as you can control the permission level.
"""
struct User
	username::String
	token::String
end
struct AuthenticatedUser
	user::User
	auth::String
end
struct RequestParams
	user::AuthenticatedUser
	start::UInt
	limit::UInt
end

"""
# Fields
- name: A username as it appears in BitBucket
- email: The person's work email address
- display_name: The person's full name
"""
struct Person
	name::String
	email::String
	display_name::String
end

struct Repository
	slug::String
	project_key::String
end

@enum ReviewStatus::UInt8 Approved UnApproved NeedsWork

@enum ParticipationType::UInt8 Author Reviewer Participant NotOnPR

@enum PullRequestStatus::UInt8 Open Declined Merged

parse(::Type{PullRequestStatus}, x::AbstractString) = if x == "OPEN" return Open elseif x == "DECLINED" return Declined elseif x == "MERGED" return Merged else throw("$(x) is not a valid PR Status") end
tryparse(::Type{PullRequestStatus}, x::AbstractString) = if x == "OPEN" return Open elseif x == "DECLINED" return Declined elseif x == "MERGED" return Merged else return nothing end

"""
A struct to represent a single pull request.
# Fields
- link: The URL that points to the PR
"""
struct PullRequest
	title::String
	"The URL that points to the PR"
	link::String
	author::Person
	reviewers::Dict{Person, ReviewStatus}
	participants::Vector{Person}
	state::PullRequestStatus
	created_date::DateTime
	updated_date::DateTime
	repo::Repository
end

"""
    Authenticate(user::User)::AuthenticatedUser

Generates the auth token required by the API. Returns the user + token in a wrapper struct.
"""
function Authenticate(user::User)::AuthenticatedUser
	AuthenticatedUser(user, base64encode("$(user.username):$(user.token)"))
end

function CheckPRState(state::AbstractString)
	if state ∉ ["ALL", "OPEN", "DECLINED", "MERGED"]
		throw("Not a valid state")
	end
end

"""
    GetUserPRs(user::AuthenticatedUser, base_address::AbstractString; state::AbstractString="ALL", start_date::Union{Date, DateTime}=(now()-Week(4)), end_date::Union{Date, DateTime}=now(), get_all::Bool=false, page_size::UInt=UInt(50))::Vector{PullRequest}

Get the pull requests for the given user. Can specify optional arguments for filtering. By default will only return the last 4 weeks of data.

See also [`GetRepoPRs`](@ref)
"""
function GetUserPRs(user::AuthenticatedUser, base_address::AbstractString; state::AbstractString="ALL", start_date::Union{Date, DateTime}=(now()-Week(4)), end_date::Union{Date, DateTime}=now(), get_all::Bool=false, page_size::UInt=UInt(50))::Vector{PullRequest}
	CheckPRState(state)
	pr_date = now()
	there_is_more = true
	values = Vector{PullRequest}()
	params = RequestParams(user, 0, page_size)
	while (pr_date > start_date || get_all) && there_is_more
		resp =  HTTP.get("https://$(base_address)/rest/api/latest/dashboard/pull-requests?start=$(params.start)&limit=$(params.limit)$(ifelse(state=="ALL","", "&state=$(state)"))", ["Authorization"=>"Basic $(user.auth)"])
		body = JSON.parse(String(resp.body))
		append!(values, ParsePullRequest.(body["values"]))
		there_is_more = !body["isLastPage"]
		if !isempty(values)
			pr_date = values[end].updated_date
		end
		params = RequestParams(user, params.start + page_size, params.start)
	end
	if get_all
		return values
	else
		filter(x -> x.updated_date > start_date && x.updated_date < end_date, values)
	end 
	
end

"""
    GetRepoPRs(user::AuthenticatedUser, base_address::AbstractString, repo::Repository; state::AbstractString="ALL", start_date::Union{Date, DateTime}=(now()-Week(4)), end_date::Union{Date, DateTime}=now(), get_all::Bool=false, page_size::UInt=UInt(50))::Vector{PullRequest}

Get the pull requests for the given repository. Can specify optional arguments for filtering. By default will only return the last 4 weeks of data.

See also [`GetUserPRs`](@ref)
"""
function GetRepoPRs(user::AuthenticatedUser, base_address::AbstractString, repo::Repository; state::AbstractString="ALL", start_date::Union{Date, DateTime}=(now()-Week(4)), end_date::Union{Date, DateTime}=now(), get_all::Bool=false, page_size::UInt=UInt(50))::Vector{PullRequest}
	CheckPRState(state)
	pr_date = now()
	there_is_more = true
	values = Vector{PullRequest}()
	params = RequestParams(user, 0, page_size)
	while (pr_date > start_date || get_all) && there_is_more
		resp = HTTP.get("https://$(base_address)/rest/api/latest/projects/$(repo.project_key)/repos/$(repo.slug)/pull-requests?start=$(params.start)&limit=$(params.limit)&state=$(state)", ["Authorization"=>"Basic $(params.user.auth)"])
		body = JSON.parse(String(resp.body))
		append!(values, ParsePullRequest.(body["values"]))
		there_is_more = !body["isLastPage"]
		if !isempty(values)
			pr_date = values[end].updated_date
		end
		params = RequestParams(user, params.start + page_size, params.start)
	end
	if get_all
		return values
	else
		filter(x -> x.updated_date > start_date && x.updated_date < end_date, values)
	end 
end

function ShortenDisplayName(name::AbstractString)::AbstractString
	names = split(name)
	if length(names) > 1
		return "$(names[1]) $(uppercase(names[end][1]))."
	else
		return name
	end
end

function EncodeReviewStatus(review_status::String)::ReviewStatus
	if review_status[1] == 'U'
		return UnApproved
	elseif review_status[1] == 'A'
		return Approved
	elseif review_status[1] == 'N'
		return NeedsWork
	else
		throw("$(review_status) is not a review status")
	end
end

function Person(data::Dict{String, Any})::Person
	return Person(data["name"], get(data, "emailAddress", "N/A"), data["displayName"])
end

parse(::Type{Person}, x::Dict{String, Any}) = Person(x)

function GetReviewers(data::Dict{String, Any})::AbstractDict{Person, ReviewStatus}
	reviewers = Dict{Person, ReviewStatus}()
	r = data["reviewers"]
	for user in r
		u = user["user"]
		p = Person(u)
		push!(reviewers, p => EncodeReviewStatus(user["status"]))
	end
	return reviewers
end

function GetParticipants(data::Dict{String, Any})::AbstractVector{Person}
	participants = Vector{Person}()
	p = data["participants"]
	for user in p
		u = user["user"]
		p = Person(u)
		push!(participants, p)
	end
	return participants
end

function GetAuthor(data::Dict{String, Any})::Person
	u = data["author"]["user"]
	return Person(u)
end

function GetAllPeopleOnPR(pr::PullRequest)
	people = Vector{Person}()
	append!(people, keys(pr.reviewers), pr.participants)
	push!(people, pr.author)
end

"""
    GetRole(username::String, pr::PullRequest)::ParticipationType

Returns the role of the person with the given username on the given pull request. Returns `NotOnPR` if the person does not appear on the pull request.
"""
function GetRole(username::String, pr::PullRequest)::ParticipationType
	reviewers = keys(pr.reviewers)
	participants = pr.participants
	author = pr.author
	if username in [r.name for r in reviewers]
		return Reviewer
	elseif username in [p.name for p in participants]
		return Participant
	elseif username == author.name
		return Author
	else
		return NotOnPR
	end
end


"""
    GetRole(username::String, pr::PullRequest)::ParticipationType

Returns the person's role on the pull request. Returns `NotOnPR` if the person does not appear on the pull request.
"""
function GetRole(person::Person, pr::PullRequest)::ParticipationType
	reviewers = keys(pr.reviewers)
	participants = pr.participants
	author = pr.author
	if person in reviewers
		return Reviewer
	elseif person in participants
		return Participant
	elseif person == author
		return Author
	else
		return NotOnPR
	end
end

function ParsePullRequest(data::Dict{String, Any})::PullRequest
	PullRequest(data["title"], data["links"]["self"][1]["href"], GetAuthor(data), GetReviewers(data), GetParticipants(data), parse(PullRequestState, data["state"]), unix2datetime(data["createdDate"] / 1000),  unix2datetime(data["updatedDate"] / 1000), Repository(data["toRef"]["repository"]["slug"], data["toRef"]["repository"]["project"]["key"]))
end

end
