
import XRC "canister:xrc";

import Buffer "mo:base/Buffer"; 
import ICRC2_T "ICRC2_Types";

module {
  // types
  public type DepositAmount = Nat;
  public type UUID = Text;
  public type UUIDBuffer = Buffer.Buffer<UUID>;

  // state of deposit and withdraw operations
  public type LoanState = {
    depositTransfer: Bool;
    depositMint : Bool;
    withdrawTransfer : Bool;
    withdrawBurn : Bool;
    inProgress : Bool;
  };

  public type DepositState = {
    satoshiesAtDeposit : Nat;
    usdtRateAtDeposit: Nat64;
    mintAmount: Nat;
  };

  public type Loan = {
    uuid: UUID;
    principal: Principal;
    deposit : DepositState;
    state: LoanState;
  };

  type TokenTransferType = { #TransferFrom; #Transfer };

  public type TokenTransferArgs = {
    destination: Principal;
    amount: DepositAmount;
    tokenActor: ICRC2_T.TokenInterface;
    transferType: TokenTransferType;
  };

  // Errors

  // general loan fetching error
  public type LoanError = {
    #LoanNotFound: { uuid: Text };
  };

  public type XRCError = {
    #ExchangeRateError: XRC.ExchangeRateError;
  };

  // icrc2 token transfer errors
  public type TokenTransferError = {
    #TransferFailed : { message : Text };
    #MintFailed : { message : Text };
    #TransferFrom : ICRC2_T.TransferFromError;
    #Transfer: ICRC2_T.TransferError;
  };

  // combines errors for deposit and withdraw operations
  public type TransferError = {
    #InProgress: { uuid: Text };
    #TokenTransfer : { error: TokenTransferError; uuid: Text };
    #Loan : LoanError;
    #ReachedUnknownState: { uuid: Text };
    #ExchangeRate : XRCError;
  };
}
