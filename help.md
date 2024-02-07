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
dfx canister call borrow deposit '(20_000)' --identity $USER_PRINCIPAL_NAME
```

```
dfx canister call borrow withdraw '("f15a2991-6632-4a4e-a64e-523f3c236c1a")' --identity $USER_PRINCIPAL_NAME
```

### Query
```
dfx canister call borrow getLoanByUUID '("f15a2991-6632-4a4e-a64e-523f3c236c1a")'
```

```
dfx canister call borrow getLoansByPrincipal "(principal \"$USER_PRINCIPAL\")"
```
