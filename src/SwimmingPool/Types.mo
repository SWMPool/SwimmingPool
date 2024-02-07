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

  public type Loan = {
    uuid: UUID;
    principal: Principal;
    depositAmount : DepositAmount;
    state: LoanState;
  };

  public type TokenTransferArgs = {
    destination: Principal;
    amount: DepositAmount;
    tokenActor: ICRC2_T.TokenInterface;
    typeOfTransfer: Text;
  };

  public type LoanError = {
    #LoanNotFound: { uuid: Text };
  };

  public type TransferError = {
    #TransferFailed : { message : Text };
    #MintFailed : { message : Text };
    #TransferFromError : ICRC2_T.TransferFromError;
  };

  public type DepositError = {
    #DepositInProgress: { uuid: Text };
    #ReachedUnknownState: { uuid: Text };
    #TransferError : { error: TransferError ; uuid: Text };
    #LoanError : LoanError;
  };

  public type WithdrawError = {
    #WithdrawInProgress: { uuid: Text };
    #TransferError : { error: TransferError ; uuid: Text };
    #LoanError : LoanError;
    #ReachedUnknownState: { uuid: Text };
  }
}
