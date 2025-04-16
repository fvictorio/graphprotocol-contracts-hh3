# Still pending

* Double-check it supports paying per byte instead of per entity and eventually a subgraph-gas metric. DONE: ~~Built-in upgrade path to indexing agreements v2~~
* Update Arbitration Charter to support disputing Indexing Fees. DONE: ~~Support `DisputeManager`~~
* Economics
  * If service wants to collect more than collector allows. Collector limits but doesn't tell the service?
  * Support for agreements that end up in `RecurringCollectorCollectionTooLate` or ways to avoid getting to that state.
  * Should we deal with zero entities declared as a special case?
  * Since an allocation is required for collecting, do we want to expect that the allocation is not stale? Do we want to add code to collect rewards as part of the collection of fees? Make sure allocation is more than one epoch old if we attempt this.
  * Reject Zero POIs?
  * What happens if the escrow doesn't have enough funds? Since you can't collect that means you lose out forever?
  * Don't pay for entities on initial collection?
  * Should we set a different param for initial collection time max? Some subgraphs take a lot to catch up.
  * How do we solve for the case where an indexer has reached their max expected payout for the initial sync but haven't reached the current epoch (thus their POI is incorrect)?
* Double check cancelation policy. Who can cancel when? Right now is either party at any time.
* Expose a function that indexers can use to calculate the tokens to be collected and other collection params?
* Support a way for gateway to shop an agreement around? Deadline + dedup key? So only one agreement with the dedupe key can be accepted?
* Maybe check that the epoch the indexer is sending is the one the transaction will be run in?
* Check upgrade conditions. Support indexing agreement upgadeability, so that there is a mechanism to adjust the rates without having to cancel and start over.
* If an indexer closes an allocation, what should happen to the accepeted agreement?
* test_SubgraphService_CollectIndexingFee_Integration fails with PaymentsEscrowInconsistentCollection
* Reduce the number of errors declared and returned
* DONE: ~~Make `agreementId` unique globally so that we don't need the full tuple (`payer`+`indexer`+`agreementId`) as key?~~
* DONE: ~~Maybe IRecurringCollector.cancel(address payer, address serviceProvider, bytes16 agreementId) should only take in agreementId?~~
* DONE: ~~Unify to one error in Decoder.sol~~
* Missing events for accept, cancel, upgrade RCAs.
