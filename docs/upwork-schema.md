# Upwork GraphQL, verified against the live API

Spike run 2026-09-08 with a real approved key. Everything below was confirmed by
executing it, not read from a public repo. This supersedes the guesses in the
design doc.

## Granted vs blocked

**Correction, 2026-09-24.** Earlier versions of this file and the README said
flatly that no proposal-submit mutation exists. That was overstated. Upwork's
API key request form offers a **`Submit Proposal`** permission, described as
"Grants access to submit proposal to jobs". What was verified here is narrower:
that scope was not requested on this key, so no submit mutation was reachable.
Radar still has no submit path and must never get one, because auto-bidding is
a permanent ban under the Acceptable Use policy regardless of the API surface.

| Probe | Result |
|---|---|
| `marketplaceJobPostingsSearch` | **GRANTED** |
| `marketplaceJobPosting(id:)` detail | **GRANTED** |
| `user`, `organization` | **GRANTED** |
| `publicMarketplaceJobPostingsSearch` | BLOCKED, scope not on the token |
| `roomsV2` (messaging) | BLOCKED, scope not on the token |
| `connectsBalance` | BLOCKED, scope not requested |

The blocked ones do not matter to the core loop. `publicMarketplaceJobPostingsSearch`
was only ever a fallback and can be deleted.

## Query signature (confirmed)

```graphql
marketplaceJobPostingsSearch(
  marketPlaceJobFilter: MarketplaceJobPostingsSearchFilter
  searchType: MarketplaceJobPostingSearchType   # only value: USER_JOBS_SEARCH
  sortAttributes: [MarketplaceJobPostingSearchSortAttribute]  # { field: RECENCY }
): MarketplaceJobPostingSearchConnection
```

`MarketplaceJobPostingSearchSortField`: `RECENCY`, `RELEVANCE`,
`CLIENT_TOTAL_CHARGE`, `CLIENT_RATING`.

## Filter inputs: every key carries an `_eq` / `_any` / `_all` suffix

This is the single biggest correction. The previous implementation sent
`searchExpression` and `contractType`, neither of which exists.

```
searchExpression_eq      String        titleExpression_eq      String
skillExpression_eq       String        searchTerm_eq           SearchTerm
jobType_eq               ContractType  # HOURLY | FIXED
duration_any             JobDuration   workload_eq             EngagementType
hourlyRate_eq            IntRange      budgetRange_eq          IntRange
clientHiresRange_eq      IntRange      proposalRange_eq        IntRange
verifiedPaymentOnly_eq   Boolean       previousClients_eq      Boolean
experienceLevel_eq       ExperienceLevel
daysPosted_eq            Int           locations_any           String
categoryIds_any          ID            occupationIds_any       ID
ontologySkillIds_all     ID            pagination_eq           Pagination
```

`Pagination { after: String, first: Int }`. `after` is a numeric offset as a
string, so `{first: 5, after: "0"}` works. `IntRange { rangeStart, rangeEnd }`.

**`proposalRange_eq` and `daysPosted_eq` let the server do the early-applicant
filtering that the local scorer currently approximates.**

## Result node: `MarketplaceJobPostingSearchResult`

Connection is `edges { cursor node }` where the edge type is
`MarketplaceJobpostingSearchEdge` (note the lowercase `p`).

Confirmed present and useful:

```
id  ciphertext  title  description  recordNumber
publishedDateTime  createdDateTime  renewedDateTime
totalApplicants     Int      # live competition count
applied             Boolean  # whether Farzam already bid
premium  enterprise  freelancersToHire  totalFreelancersToHire
category  subcategory  experienceLevel  engagement  durationLabel  duration
preferredFreelancerLocation  preferredFreelancerLocationMandatory
hourlyBudgetType    # DEFAULT | MANUAL | NOT_PROVIDED
hourlyBudgetMin  hourlyBudgetMax  amount  weeklyBudget   # all Money
skills { name prettyName highlighted }
client { ... }
relevance  relevanceEncoded  freelancerClientRelation
```

**There is no `contractType` on the search result.** `amount.rawValue > 0` means
fixed price; otherwise it is hourly, and `hourlyBudgetMin/Max` carry the range.
The authoritative value is `contractTerms.contractType` on the detail query.

`Money { rawValue: String, currency: String, displayValue: String }`. rawValue is
a **string**, so it must be cast before arithmetic.

`client`: `totalHires`, `totalPostedJobs`, `totalReviews`, `totalFeedback` (Float,
this is the rating), `totalSpent` (Money), `verificationStatus`
(`VERIFIED` or empty), `location { city country state timezone offsetToUTC }`.

## Detail query, for screening questions

```graphql
marketplaceJobPosting(id: ID!) {
  content { title description }
  contractTerms { contractType }
  contractorSelection {
    proposalRequirement { coverLetterRequired screeningQuestions { question sequenceNumber } }
    qualification { englishProficiency risingTalent hasPortfolio jobSuccessScore hoursWorked }
    location { countries }
  }
}
```

Confirmed working on live jobs. One Rails posting returned five real screening
questions. This is what lets the generator answer them before Farzam opens the job.

Fields on this type that are **blocked** by our scopes and must not be requested:
`activityStat.applicationsBidStats.*`, `jobActivity.totalApplicants`,
`location.regions`, `qualification.minJobSuccessScore`,
`qualification.shouldHavePortfolio`. Asking for any of them fails the whole query.

## Introspection is rate-shaped

Upwork rejects introspection queries that ask for `__Type.inputFields` more than
once per request: "This request is not asking for introspection in good faith".
Introspect one type per request.

## Auth

`client_credentials` is rejected with `unauthorized_client`. The authorization
code flow is required, with a real https redirect. Token lifetime is 24 hours and
the refresh token works.
