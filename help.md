# Initial setup and upgrade

### export all needed variables
```
chmod +x ./scripts/export.sh
. ./scripts/export.sh
```

### deploy all canisters
```
chmod +x ./scripts/deploy_all.sh
. ./scripts/deploy_all.sh
```

###  force upgrade borrow
```
chmod +x ./scripts/upgrade_borrow.sh
. ./scripts/upgrade_borrow.sh
```

# Calls
## Approval
```
dfx canister call collateral_token icrc2_approve "(record {
    spender = record { owner = principal \"$(dfx canister id borrow)\" };
    amount = 1_000_000;
  })" --identity $USER_PRINCIPAL_NAME
```

```
dfx canister call stable_token icrc2_approve "(record {
    spender = record { owner = principal \"$(dfx canister id borrow)\" };
    amount = 1_000_000;
  })" --identity $USER_PRINCIPAL_NAME
```

## Balance Check
```
dfx canister call collateral_token icrc1_balance_of "(record {
    owner = principal \"$(dfx canister id borrow)\" 
  })"
```

```
dfx canister call collateral_token icrc1_balance_of "(record {
    owner = principal \"$USER_PRINCIPAL\" 
  })"
```

```
dfx canister call stable_token icrc1_balance_of "(record {
    owner = principal \"$(dfx canister id borrow)\"
  })"
```

```
dfx canister call stable_token icrc1_balance_of "(record {
    owner = principal \"$USER_PRINCIPAL\" 
  })"
```

## Borrow canister
### Shared
```
dfx canister call borrow deposit '(10_000)' --identity $USER_PRINCIPAL_NAME
```

### Query
```
dfx canister call borrow getLoanByUUID '("e1329829-6927-46c7-b6e9-a5db74db0f31")'
```
