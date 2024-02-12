import { expect, test } from "vitest";
import { Principal } from "@dfinity/principal";
import { collateralTokenActor } from "./actorCollateral";
import { borrowCanisterId, borrowActor} from "./actorBorrower"
import { stableTokenActor} from "./actorStable"
import { Result } from "../declarations/borrow/borrow.did"
import { Allowance } from "../declarations/stable_token/stable_token.did"

let loanId: string;
let initialBalance: bigint;
test("should approve trasnfer from collateral", async () => {
  initialBalance = await collateralTokenActor.icrc1_balance_of({
    owner: Principal.fromText(process.env.USER_PRINCIPAL as string),
    subaccount: []
  }) as bigint;

  const approveAllowanceForBorrower = await collateralTokenActor.icrc2_approve({
    fee: [],
    amount: 1000000n,
    memo: [],
    from_subaccount: [],
    created_at_time: [],
    expected_allowance: [],
    expires_at: [],
    spender: {
        owner: Principal.fromText(borrowCanisterId),
        subaccount: []
    }
  });
  const allowanceForBorrower = await collateralTokenActor.icrc2_allowance({
    account: {
        owner: Principal.fromText(process.env.USER_PRINCIPAL as string),
        subaccount: []
    },
    spender: {
        owner: Principal.fromText(borrowCanisterId),
        subaccount: []
    }
  }) as Allowance;

  expect(allowanceForBorrower.allowance).toEqual(1000000n);
});

test("should deposit", async () => {
  const result = await borrowActor.deposit(200000n) as Result;

  if (result.hasOwnProperty("ok")){
    loanId = result['ok'];
  }
  expect(result).toHaveProperty('ok');
}, 70000);

test("should approve transfer from stable", async () => {
  const balance = await stableTokenActor.icrc1_balance_of({
    owner: Principal.fromText(process.env.USER_PRINCIPAL as string),
    subaccount: []
  });

  const _ = await stableTokenActor.icrc2_approve({
    fee: [],
    amount: balance,
    memo: [],
    from_subaccount: [],
    created_at_time: [],
    expected_allowance: [],
    expires_at: [],
    spender: {
        owner: Principal.fromText(borrowCanisterId),
        subaccount: []
    }
  });
  
  const result2 = await stableTokenActor.icrc2_allowance({
    account: {
        owner: Principal.fromText(process.env.USER_PRINCIPAL as string),
        subaccount: []
    },
    spender: {
        owner: Principal.fromText(borrowCanisterId),
        subaccount: []
    }
  }) as Allowance;
  
  expect(result2.allowance).toEqual(balance);
});

test("should withdraw", async () => {
  const result = await borrowActor.withdraw(loanId);

  expect(result).toHaveProperty('ok');
})

test("should have current balance equal to initial balance", async () => {
  let currentBalance = await collateralTokenActor.icrc1_balance_of({
    owner: Principal.fromText(process.env.USER_PRINCIPAL as string),
    subaccount: []
  }) as bigint;

  expect(currentBalance).toEqual(initialBalance);
})