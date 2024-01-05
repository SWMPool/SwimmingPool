![swimming_pool](https://raw.githubusercontent.com/SWMPool/SwimmingPool/main/swimming_pool_system_design.jpg)

**1. The Swimming Pool Router** - manages and directs user requests within the swimming pool system.
**2. Swimming Pool Treasury** - allocates separate treasuries for each asset within the swimming pool, ensuring separate asset management. The assets are deposited there.
**3. Swimming Pool Accounting** - a single contract that t centralizes the accounting function. Oversees risk management measures and performs collateralization checks. This contract uses the Exchange Rate Canister.
**4. The Swimming Pool Mint Router** - facilitates the creation and distribution of SWP Stablecoins.
**5. Backend** - oversees and facilitates events of liquidation.
