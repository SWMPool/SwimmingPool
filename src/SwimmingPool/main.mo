import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Buffer "mo:base/Buffer"; 
import Result "mo:base/Result";
import Option "mo:base/Option";
import HashMap "mo:base/HashMap";
import Error "mo:base/Error";
import Debug "mo:base/Debug";

import LibUUID "mo:uuid/UUID";
import Source "mo:uuid/async/SourceV4";

import ICRC2_T "ICRC2_Types";
import T "Types";

shared ({ caller = _owner }) actor class Borrow(
  initArgs : {
    collateralToken : Principal;
    stableToken : Principal;
  }
) = this {
  // token actors
  private let collateralTokenActor : ICRC2_T.TokenInterface = actor (Principal.toText(initArgs.collateralToken));
  private let stableTokenActor : ICRC2_T.TokenInterface = actor (Principal.toText(initArgs.stableToken));
  private let uuidGenerator = Source.Source();

  private let initialBufferCapacity = 10;
  // fast access to a loan by its UUID
  private let loanByUUID = HashMap.HashMap<T.UUID, T.Loan>(initialBufferCapacity, Text.equal, Text.hash);
  // array to maintain order of loans
  private let activeLoans: T.UUIDBuffer = Buffer.Buffer<T.UUID>(initialBufferCapacity);
  // fast access to loans by principal
  private let loansByPrincipal = HashMap.HashMap<Principal, T.UUIDBuffer>(initialBufferCapacity, Principal.equal, Principal.hash);

  // SHARED METHODS
  // Accept deposits
  // - user approves transfer: `token_a.icrc2_approve({ spender=borrow_canister; amount=amount; ... })`
  // - user deposits their token: `borrow_canister.deposit(amount)`
  public shared ({ caller }) func deposit(amount : T.DepositAmount) : async Result.Result<T.UUID, T.DepositError> {
    let loan = await newLoan(caller, amount);
    return await depositHelper(loan.uuid);
  };

  // Retry deposit in case it fails at some point
  // TODO: is caller check needed? At this point the loan should be in the system with the correct principal.
  public func depositRetry(loanUUID: T.UUID) : async Result.Result<T.UUID, T.DepositError> {
    return await depositHelper(loanUUID);
  };

  // QUERY METHODS
  public query func getLoanByUUID(loanUUID: T.UUID) : async Result.Result<T.Loan, T.LoanError> {
    return getLoan(loanUUID);
  };

  public query func getLoansByPrincipal(principal: Principal) : async Result.Result<[T.Loan], T.LoanError> {
    switch (loansByPrincipal.get(principal)) {
      case (?uuids) {
        // mapFilter drops all null 
        let loansData: Buffer.Buffer<T.Loan> = Buffer.mapFilter<T.UUID, T.Loan>(uuids, func (uuid: T.UUID) {
          switch (getLoan(uuid)) {
            case (#ok(loan)) { ?loan };
            case (#err(err)) { null };
          };
        });
        
        return #ok(Buffer.toArray(loansData));
      };
      case (_) {
        return #ok([]);
      };
    };
  };

  // PRIVATE METHODS
  // internal method that handles deposit logic
  private func depositHelper(loanUUID: T.UUID) : async Result.Result<T.UUID, T.DepositError> {
    switch (getLoan(loanUUID)) {
      case (#ok(loan)) {
        var mutableLoan = loan;

        // Handle the case where a deposit is in progress.
        if (mutableLoan.state.inProgress == true) {
          return #err(#DepositInProgress({ uuid = loanUUID }));
        };

        // call transfer
        if (mutableLoan.state.depositTransfer == false and mutableLoan.state.depositMint == false) {
          // lock
          mutableLoan := { mutableLoan with state = { mutableLoan.state with inProgress = true } };
          let _ = updateLoan(mutableLoan);

          let transferResult = await transfer(mutableLoan.principal, mutableLoan.depositAmount);
          switch (transferResult) {
            case (#ok(_)) {
              // update state with successful transfer and release lock
              mutableLoan := { mutableLoan with state = { mutableLoan.state with depositTransfer = true; inProgress = false } };
              let _ = updateLoan(mutableLoan);
            };
            case (#err(error)) {
              // release lock
              mutableLoan := { mutableLoan with state = { mutableLoan.state with inProgress = false } };
              let _ = updateLoan(mutableLoan);
              return #err(#TransferError{ error; uuid = loanUUID });
            };
          };
        };

        // call mint
        if (mutableLoan.state.depositTransfer == true and mutableLoan.state.depositMint == false) {
          // lock
          mutableLoan := { mutableLoan with state = { mutableLoan.state with inProgress = true } };
          let _ = updateLoan(mutableLoan);

          let mintResult = await mint(mutableLoan.principal, mutableLoan.depositAmount);
          switch (mintResult) {
            case (#ok(_)) {
              // update state with successful mint and release lock
              mutableLoan := { mutableLoan with state = { mutableLoan.state with depositMint = true; inProgress = false } };
              let _ = updateLoan(mutableLoan);
            };
            case (#err(error)) {
              // release lock
              mutableLoan := { mutableLoan with state = { mutableLoan.state with inProgress = false } };
              let _ = updateLoan(mutableLoan);
              return #err(#TransferError{ error; uuid = loanUUID });
            };
          };
        };

        // end state
        if (mutableLoan.state.depositTransfer == true and mutableLoan.state.depositMint == true) {
          return #ok(mutableLoan.uuid);
        };

        return #err(#ReachedUnknownState({ uuid = loanUUID }));
      };
      case (#err(err)) {
        return #err(#LoanError(err));
      };
    };
  };

  // TODO: fee calculations?
  public func transfer(caller: Principal, amount : T.DepositAmount) : async Result.Result<T.DepositAmount, T.TransferError> {
    try {
      // Perform the transfer, to capture the tokens.
      let transferResult = await collateralTokenActor.icrc2_transfer_from({
        amount;
        from = { owner = caller; subaccount = null };
        to = { owner = Principal.fromActor(this); subaccount = null };
        spender_subaccount = null;
        fee = null;
        memo = null;
        created_at_time = null;
      });

      // Check that the transfer was successful.
      let transfer = switch (transferResult) {
        case (#Ok(_)) { #ok(amount) };
        case (#Err(err)) { return #err(#TransferFromError(err)); };
      };
    } catch (err) {
      return #err(#TransferFailed({ message = Error.message(err) }));
    };
  };

  // TODO: fee calculations?
  private func mint(caller: Principal, amount : T.DepositAmount) : async Result.Result<T.DepositAmount, T.TransferError> {
    try {
      // Perform the transfer, to mint the tokens to the caller.
      let mintResult = await stableTokenActor.icrc1_transfer({
        to = { owner = caller; subaccount = null };
        amount = amount;
        from_subaccount = null;
        memo = null;
        fee = null;
        created_at_time = null;
      });

      // Check that the transfer was successful.
      let transfer = switch (mintResult) {
        case (#Ok(_)) { #ok(amount) };
        case (#Err(err)) { return #err(#TransferFromError(err)); };
      };

    } catch (err) {
      return #err(#MintFailed({ message = Error.message(err) }));
    };
  };

  // LOAN HANDLERS
  private func newLoan(principal: Principal, depositAmount : T.DepositAmount) : async T.Loan {
    let loan = {
      uuid = LibUUID.toText(await uuidGenerator.new());
      principal;
      depositAmount;
      state = {
        depositTransfer = false;
        depositMint = false;
        withdrawTransfer = false;
        withdrawBurn = false;
        inProgress = false
      };
    };

    let _ = loanByUUID.put(loan.uuid, loan);
    let _ = activeLoans.add(loan.uuid);
    let _ = Option.get(loansByPrincipal.get(loan.principal), Buffer.Buffer<T.UUID>(initialBufferCapacity)).add(loan.uuid);

    loan
  };

  private func deleteLoan(loanUUID: T.UUID) : Result.Result<T.Loan, T.LoanError> {
    let loan = loanByUUID.get(loanUUID);
    switch (loan) {
      case (?loan) {
        activeLoans.filterEntries(func (_, uuid) { uuid == loanUUID });
        return #ok(loan);
      };
      case (_) {
        return #err(#LoanNotFound({ uuid = loanUUID }));
      };
    };
  };

  private func updateLoan(loan: T.Loan): Result.Result<T.UUID, T.LoanError> {
    let oldLoanData = loanByUUID.replace(loan.uuid, loan);
    switch (oldLoanData) {
      case (?loan) {
        return #ok(loan.uuid);
      };
      case (_) {
        return #err(#LoanNotFound({ uuid = loan.uuid }));
      };
    };
  };

  private func getLoan(loanUUID: T.UUID) : Result.Result<T.Loan, T.LoanError> {
    let loan = loanByUUID.get(loanUUID);
    switch (loan) {
      case (?loan) {
        return #ok(loan);
      };
      case (_) {
        return #err(#LoanNotFound({ uuid = loanUUID }));
      };
    };
  };
};