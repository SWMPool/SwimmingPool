# Swimming Pool
### Collateralised Stablecoin Protocol
Swimming Pool is designed as a set of smart contracts to generate a risk-balanced, collateralised native stablecoin for the ICP ecosystem.
Crypto assets have differing yet high, specific risk, high correlations and implicit leverage. Swim- ming Pool is built upon single ‘Local’ asset-collateralised borrowing pools that create their own USD1 denominated stablecoins. Each Local stablecoin can be used (spent), or added to a global liquidity pool which generates the Swimming Pool basket of assets - the ‘Meta’ stablecoin.

## System Design
![swimming_pool](https://raw.githubusercontent.com/SWMPool/SwimmingPool/main/swimming_pool_system_design.jpg)

## Note
Not every block in the diagram represents a separate Canister. The separation in the diagram is done for clarity. We will try to use as few canisters as possible because the transactions are not atomic between them.

1. The Swimming Pool Router - manages and directs user requests within the swimming pool system.
2. Swimming Pool Treasury - allocates separate treasuries for each asset within the swimming pool, ensuring separate asset management. The assets are deposited there.
3. Swimming Pool Accounting - a single contract that t centralizes the accounting function. Oversees risk management measures and performs collateralization checks. This contract uses the Exchange Rate Canister.
4. The Swimming Pool Mint Router - facilitates the creation and distribution of SWP Stablecoins.
5. Timer Triggered Canister - a canister that utilizes timers to do periodic checks and perform liquidations where necessary.

