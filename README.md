# Swimming Pool

### Collateralised Stablecoin Protocol

Swimming Pool is designed as a set of smart contracts to generate a risk-balanced, collateralised native stablecoin for the ICP ecosystem.
Crypto assets have differing yet high, specific risks, high correlations, and implicit leverage. Swimming Pool is built upon single ‘Local’ asset-collateralised borrowing pools that create their own USD denominated stablecoins. Each Local stablecoin can be used (spent), or added to a global liquidity pool which generates the Swimming Pool basket of assets - the ‘Meta’ stablecoin.

## System Design

![swimming_pool](https://github.com/SWMPool/SwimmingPool/blob/main/SwimmingPools.png?raw=true)

## Note

Not every block in the diagram represents a separate Canister. The separation in the diagram is done for clarity. We will try to use as few canisters as possible because the transactions are not atomic between them.

1. The Swimming Pool Router manages and directs user requests within the swimming pool system.
2. Swimming Pool Treasury allocates separate treasuries for each asset within the swimming pool, ensuring separate asset management. The assets are deposited there.
3. Swimming Pool Accounting is a single contract that centralizes the accounting function. Oversees risk management measures and performs collateralization checks. This contract uses the Exchange Rate Canister.
4. The Swimming Pool Mint Router facilitates the creation and distribution of SWP Stablecoins.
5. Timer Triggered Canister is a canister that utilizes timers to do periodic checks and perform liquidations where necessary.


# BORROW

Welcome to your new borrow project and to the internet computer development community. By default, creating a new project adds this README and some template files to your project directory. You can edit these template files to customize your project and to include your own code to speed up the development cycle.

To get started, you might want to explore the project directory structure and the default configuration file. Working with this project in your development environment will not affect any production deployment or identity tokens.

To learn more before you start working with borrow, see the following documentation available online:

- [Quick Start](https://internetcomputer.org/docs/current/developer-docs/setup/deploy-locally)
- [SDK Developer Tools](https://internetcomputer.org/docs/current/developer-docs/setup/install)
- [Motoko Programming Language Guide](https://internetcomputer.org/docs/current/motoko/main/motoko)
- [Motoko Language Quick Reference](https://internetcomputer.org/docs/current/motoko/main/language-manual)

If you want to start working on your project right away, you might want to try the following commands:

```bash
cd borrow/
dfx help
dfx canister --help
```

## Running the project locally

If you want to test your project locally, you can use the following commands:

```bash
#install dependencies
mops install
# Starts the replica, running in the background
dfx start --background --clean

# Deploys your canisters to the replica and generates your candid interface
dfx deploy
```

Once the job completes, your application will be available at `http://localhost:4943?canisterId={asset_canister_id}`.

If you have made changes to your backend canister, you can generate a new candid interface with

```bash
npm run generate
```

at any time. This is recommended before starting the frontend development server, and will be run automatically any time you run `dfx deploy`.

If you are making frontend changes, you can start a development server with

```bash
npm start
```

Which will start a server at `http://localhost:8080`, proxying API requests to the replica at port 4943.

## Testing locally
To run tests there are couple of prerequisites, first you need your 24 seed phrases, if you don't have them saved, create a new account by running
```bash
dfx identity new <NAME>
```
with the newly aquired seed phrases navigate to `src/tests/identity.ts` paste them in the `seed` variable.
Next, run the network locally by running
```bash
dfx start --background --clean
```
navigate to scripts/export.sh make sure that `USER_PRINCIPAL` and `USER_PRINCIPAL_NAME` are set to the ones you've created earlier, if you are unsure how to get your Principal, you can do that by
```bash
dfx identity get-principal --identity <NAME>
```
Next, run the deploy all script and after all the canisters have been deployed, run
```bash
dfx generate
```
this will create a `declarations` folder which we need, follow it by
```bash
npm install
```
which will install the testing library we are using and some other needed modules. Run the tests by 
```bash
npm test // make sure to call . ./scripts/export.sh in the same terminal before you run the tests
```

### Note on frontend environment variables

If you are hosting frontend code somewhere without using DFX, you may need to make one of the following adjustments to ensure your project does not fetch the root key in production:

- set`DFX_NETWORK` to `ic` if you are using Webpack
- use your own preferred method to replace `process.env.DFX_NETWORK` in the autogenerated declarations
  - Setting `canisters -> {asset_canister_id} -> declarations -> env_override to a string` in `dfx.json` will replace `process.env.DFX_NETWORK` with the string in the autogenerated declarations
- Write your own `createActor` constructor
