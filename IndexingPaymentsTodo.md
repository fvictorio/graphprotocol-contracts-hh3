### Still pending

* Rename `agreementId` to `voucherId`?
* Update `DisputeManager` and Arbitration Charter to support disputing Indexing Fees.
* Support indexing agreement upgadeability, so that there is a mechanism to adjust the rates without having to cancel and start over.
* Built-in upgrade path to indexing agreements v2. So that indexers can be paid per byte instead of per entity.
* Support for agreements that end up in `RecurringCollectorCollectionTooLate` or ways to avoid getting to that state.
* Should we deal with zero entities declared as a special case?
* Since an allocation is required for collecting, do we want to expect that the allocation is not stale? Do we want to add code to collect rewards as part of the collection of fees? Make sure allocation is more than one epoch old if we attempt this.
* Reject Zero POIs?
* What happens if the escrow doesn't have enough funds? Since you can't collect that means you lose out forever?
* Expose a function that indexers can use to calculate the tokens to be collected and other collection params?
