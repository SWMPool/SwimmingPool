import XRC "canister:xrc";

import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Result "mo:base/Result";
import Option "mo:base/Option";
import HashMap "mo:base/HashMap";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Cycles "mo:base/ExperimentalCycles";
import Nat64 "mo:base/Nat64";

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
  // Token actors
  private let collateralTokenActor : ICRC2_T.TokenInterface = actor (Principal.toText(initArgs.collateralToken));
  private let stableTokenActor : ICRC2_T.TokenInterface = actor (Principal.toText(initArgs.stableToken));
  private let uuidGenerator = Source.Source();

  // Data storage
  private let initialBufferCapacity = 10;
  // fast access to a loan by its UUID
  private var loanByUUID = HashMap.HashMap<T.UUID, T.Loan>(initialBufferCapacity, Text.equal, Text.hash);
  // array to maintain order of loans
  private var activeLoans : T.UUIDBuffer = Buffer.Buffer<T.UUID>(initialBufferCapacity);
  // fast access to loans by principal
  private var loansByPrincipal = HashMap.HashMap<Principal, T.UUIDBuffer>(initialBufferCapacity, Principal.equal, Principal.hash);

  // Stable storage
  private stable var loanByUUIDStable : [(T.UUID, T.Loan)] = [];
  private stable var activeLoansStable : [T.UUID] = [];
  private stable var loansByPrincipalStable : [(Principal, [T.UUID])] = [];

  // Constants for xrc
  private let tenPowerOfEight : Nat64 = 100000000;
  private let tenPowerOfThree : Nat64 = 1000;


  // SHARED METHODS
  // Accept deposits
  // - user approves transfer: `token_a.icrc2_approve({ spender=borrow_canister; amount=amount; ... })`
  // - user deposits their token: `borrow_canister.deposit(amount)`
  public shared ({ caller }) func deposit(amount : T.DepositAmount) : async Result.Result<T.UUID, T.TransferError> {
    let loan = await newLoan(caller, amount);
    return await depositHelper(loan.uuid);
  };

  // Withdraw deposits
  // Accept deposits
  // - user approves transfer: `collateral_token.icrc2_approve({ spender=borrow_canister; amount=amount; ... })`
  // - user deposits their token: `borrow_canister.deposit(amount)`
  public shared ({ caller }) func withdraw(loanUUID : T.UUID) : async Result.Result<T.UUID, T.TransferError> {
    return await withdrawHelper(loanUUID);
  };

  // Retry deposit in case it fails at some point
  // TODO: is caller check needed? At this point the loan should be in the system with the correct principal.
  public func depositRetry(loanUUID : T.UUID) : async Result.Result<T.UUID, T.TransferError> {
    return await depositHelper(loanUUID);
  };

  // QUERY METHODS
  public query func getLoanByUUID(loanUUID : T.UUID) : async Result.Result<T.Loan, T.LoanError> {
    return getLoan(loanUUID);
  };

  public query func getLoansByPrincipal(principal : Principal) : async Result.Result<[T.Loan], T.LoanError> {
    switch (loansByPrincipal.get(principal)) {
      case (?uuids) {
        // mapFilter drops all null
        let loansData : Buffer.Buffer<T.Loan> = Buffer.mapFilter<T.UUID, T.Loan>(
          uuids,
          func(uuid : T.UUID) {
            switch (getLoan(uuid)) {
              case (#ok(loan)) { return ?loan; };
              case (#err(err)) { return null; };
            };
          },
        );

        return #ok(Buffer.toArray(loansData));
      };
      case (_) {
        return #ok([]);
      };
    };
  };

  // PRIVATE METHODS
  private func withdrawHelper(loanUUID : T.UUID) : async Result.Result<T.UUID, T.TransferError> {
    switch (getLoan(loanUUID)) {
      case (#ok(loan)) {
        var mutableLoan = loan;

        // Handle the case where a withdraw is in progress.
        if (mutableLoan.state.inProgress == true) {
          return #err(#InProgress({ uuid = loanUUID }));
        };

        // call transfer which in this case acts as an burning transaction
        if (mutableLoan.state.withdrawTransfer == false and mutableLoan.state.withdrawBurn == false) {
          // lock
          mutableLoan := {
            mutableLoan with state = {
              mutableLoan.state with inProgress = true
            };
          };
          let _ = updateLoan(mutableLoan);

          let burnTokens = await tokenTransfer({
            destination = mutableLoan.principal;
            amount = mutableLoan.depositAmount;
            tokenActor = stableTokenActor;
            transferType = #TransferFrom;
          });
          switch (burnTokens) {
            case (#ok(_)) {
              // update state with successful burn and release lock
              mutableLoan := {
                mutableLoan with state = {
                  mutableLoan.state with withdrawBurn = true;
                  inProgress = false;
                };
              };
              let _ = updateLoan(mutableLoan);
            };
            case (#err(error)) {
              // release lock
              mutableLoan := {
                mutableLoan with state = {
                  mutableLoan.state with inProgress = false
                };
              };
              let _ = updateLoan(mutableLoan);
              return #err(#TokenTransfer { error; uuid = loanUUID });
            };
          };
        };

        if (mutableLoan.state.withdrawTransfer == false and mutableLoan.state.withdrawBurn == true) {
          // lock
          mutableLoan := {
            mutableLoan with state = {
              mutableLoan.state with inProgress = true
            };
          };
          let _ = updateLoan(mutableLoan);

          let transferResult = await tokenTransfer({
            destination = mutableLoan.principal;
            amount = mutableLoan.depositAmount;
            tokenActor = collateralTokenActor;
            transferType = #Transfer;
          });
          switch (transferResult) {
            case (#ok(_)) {
              // update state with successful transfer and release lock
              mutableLoan := {
                mutableLoan with state = {
                  mutableLoan.state with withdrawTransfer = true;
                  inProgress = false;
                };
              };
              let _ = updateLoan(mutableLoan);
            };
            case (#err(error)) {
              // release lock and update loan state
              mutableLoan := {
                mutableLoan with state = {
                  mutableLoan.state with inProgress = false
                };
              };
              let _ = updateLoan(mutableLoan);

              // remove loan from active loans
              let _ = deleteLoan(loanUUID);

              return #err(#TokenTransfer { error; uuid = loanUUID });
            };
          };
        };

        // end state
        if (mutableLoan.state.withdrawTransfer == true and mutableLoan.state.withdrawBurn == true) {
          return #ok(mutableLoan.uuid);
        };

        return #err(#ReachedUnknownState({ uuid = loanUUID }));
      };
      case (#err(err)) {
        #err(#Loan(err));
      };
    };
  };

  // internal method that handles deposit logic
  private func depositHelper(loanUUID : T.UUID) : async Result.Result<T.UUID, T.TransferError> {
    switch (getLoan(loanUUID)) {
      case (#ok(loan)) {
        var mutableLoan = loan;

        // Handle the case where a deposit is in progress.
        if (mutableLoan.state.inProgress == true) {
          return #err(#InProgress({ uuid = loanUUID }));
        };

        // call transfer
        if (mutableLoan.state.depositTransfer == false and mutableLoan.state.depositMint == false) {
          // lock
          mutableLoan := {
            mutableLoan with state = {
              mutableLoan.state with inProgress = true
            };
          };
          let _ = updateLoan(mutableLoan);

          let transferResult = await tokenTransfer({
            destination = mutableLoan.principal;
            amount = mutableLoan.depositAmount;
            tokenActor = collateralTokenActor;
            transferType = #TransferFrom;
          });
          switch (transferResult) {
            case (#ok(_)) {
              // update state with successful transfer and release lock
              mutableLoan := {
                mutableLoan with state = {
                  mutableLoan.state with depositTransfer = true;
                  inProgress = false;
                };
              };
              let _ = updateLoan(mutableLoan);
            };
            case (#err(error)) {
              // release lock
              mutableLoan := {
                mutableLoan with state = {
                  mutableLoan.state with inProgress = false
                };
              };
              let _ = updateLoan(mutableLoan);
              return #err(#TokenTransfer { error; uuid = loanUUID });
            };
          };
        };

        // call mint
        if (mutableLoan.state.depositTransfer == true and mutableLoan.state.depositMint == false) {
          // lock
          mutableLoan := {
            mutableLoan with state = {
              mutableLoan.state with inProgress = true
            };
          };
          let _ = updateLoan(mutableLoan);
          switch(await calculateMintAmount(mutableLoan.depositAmount)){
            case (#ok(amount)){
              let mintResult = await tokenTransfer({
                destination = mutableLoan.principal;
                amount = Nat64.toNat(amount);
                tokenActor = stableTokenActor;
                transferType = #Transfer;
              });
              switch (mintResult) {
                case (#ok(_)) {
                  // update state with successful mint and release lock
                  mutableLoan := { 
                    mutableLoan with state = { 
                      mutableLoan.state with depositMint = true; inProgress = false 
                    } 
                  };
                  let _ = updateLoan(mutableLoan);
                };
                case (#err(error)) {
                  // release lock
                  mutableLoan := { 
                    mutableLoan with state = { 
                      mutableLoan.state with inProgress = false 
                    } 
                  };
                  let _ = updateLoan(mutableLoan);
                  return #err(#TokenTransfer{ error; uuid = loanUUID });
                };
              };
            };
            case (#err(err)){
              return #err(#ExchangeRate(err))
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
        return #err(#Loan(err));
      };
    };
  };

  // TODO: fee calculations?
  // single method to handle all the token transfers, this includes minting and burning as well.
  private func tokenTransfer({ destination; amount; tokenActor; transferType } : T.TokenTransferArgs) : async Result.Result<T.DepositAmount, T.TokenTransferError> {
    try {
      if (transferType == #TransferFrom) {
        let transferResult = await tokenActor.icrc2_transfer_from({
          amount;
          from = { owner = destination; subaccount = null };
          to = { owner = Principal.fromActor(this); subaccount = null };
          spender_subaccount = null;
          fee = null;
          memo = null;
          created_at_time = null;
        });

        switch (transferResult) {
          // Check that the transfer was successful.
          case (#Ok(_)) { return #ok(amount) };
          case (#Err(err)) { return #err(#TransferFrom(err)) };
        };
      };

      if (transferType == #Transfer) {
        let transferResult = await tokenActor.icrc1_transfer({
          amount;
          to = { owner = destination; subaccount = null };
          from_subaccount = null;
          memo = null;
          fee = null;
          created_at_time = null;
        });

        switch (transferResult) {
          case (#Ok(_)) { return #ok(amount) };
          case (#Err(err)) { return #err(#Transfer(err)) };
        };
      };

      return #err(#TransferFailed({ message = "Transfer type not supported!" }));
    } catch (err) {
      return #err(#TransferFailed({ message = Error.message(err) }));
    };
  };

  // LOAN HANDLERS
  private func newLoan(principal : Principal, depositAmount : T.DepositAmount) : async T.Loan {
    let loan = {
      uuid = LibUUID.toText(await uuidGenerator.new());
      principal;
      depositAmount;
      state = {
        depositTransfer = false;
        depositMint = false;
        withdrawTransfer = false;
        withdrawBurn = false;
        inProgress = false;
      };
    };

    let _ = loanByUUID.put(loan.uuid, loan);
    let _ = activeLoans.add(loan.uuid);
    let loansBuffer = loansByPrincipal.get(loan.principal);
    switch(loansBuffer) {
      case (?buffer) {
        let _ = buffer.add(loan.uuid);
      };
      case (_) {
        let buffer = Buffer.Buffer<T.UUID>(initialBufferCapacity);
        let _ = buffer.add(loan.uuid);
        let _ = loansByPrincipal.put(loan.principal, buffer);
      };
    };

    return loan;
  };

  private func deleteLoan(loanUUID : T.UUID) : Result.Result<T.Loan, T.LoanError> {
    let loan = loanByUUID.get(loanUUID);
    switch (loan) {
      case (?loan) {
        activeLoans.filterEntries(func(_, uuid) { uuid == loanUUID });
        return #ok(loan);
      };
      case (_) {
        return #err(#LoanNotFound({ uuid = loanUUID }));
      };
    };
  };

  private func updateLoan(loan : T.Loan) : Result.Result<T.UUID, T.LoanError> {
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

  private func getLoan(loanUUID : T.UUID) : Result.Result<T.Loan, T.LoanError> {
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

  // XRC METHODS
  private func getCurrentRate(): async Result.Result<Nat64, T.XRCError> {
    let request : XRC.GetExchangeRateRequest = {
      base_asset = {
        symbol = "BTC";
        class_ = #Cryptocurrency;
      };
      quote_asset = {
        symbol = "USDT";
        class_ = #Cryptocurrency;
      };
      // Get the current rate.
      timestamp = null;
    };

    // Every XRC call needs 1B cycles.
    Cycles.add(1_000_000_000);

    let response = await XRC.get_exchange_rate(request);
    let _ = switch(transformRespone(response)){
      case(#ok(value)) {#ok(value)};
      case(#err(err)) {return #err(err)};
    }
  };

  private func transformRespone(e: XRC.GetExchangeRateResult): Result.Result<Nat64, T.XRCError> {
    switch(e) {
      case (#Ok(rate_response)) {
        return #ok(rate_response.rate);
      };
      case (#Err(err)) {
        return #err(#ExchangeRateError(err));
      };
    }
  };
  // stablecoint_amount = ( (current_btc_rate / 10^3) * ckBtc_amount ) / 10^8
  private func calculateMintAmount(ckBtcAmount: Nat): async Result.Result<Nat64, T.XRCError> {
    let _ = switch(await getCurrentRate()){
      case(#ok(rate)) {
        #ok(((rate / tenPowerOfThree) * Nat64.fromNat(ckBtcAmount)) / tenPowerOfEight);
      };
      case(#err(err)) {return #err(err)};
    }
  };

  // UPGRADE METHODS
  system func preupgrade() : () {
    loanByUUIDStable := Iter.toArray<(T.UUID, T.Loan)>(loanByUUID.entries());

    activeLoansStable := Iter.toArray<T.UUID>(activeLoans.vals());

    loansByPrincipalStable := Iter.toArray<(Principal, [T.UUID])>(
      Iter.map<(Principal, T.UUIDBuffer), (Principal, [T.UUID])>(
        loansByPrincipal.entries(),
        func(entry : (Principal, T.UUIDBuffer)) {
          let (principal, buffer) = entry;
          return (principal, Buffer.toArray(buffer));
        },
      )
    );
  };

  system func postupgrade() : () {
    loanByUUID := HashMap.fromIter(Iter.fromArray(loanByUUIDStable), loanByUUIDStable.size(), Text.equal, Text.hash);

    activeLoans := Buffer.fromArray(activeLoansStable);

    loansByPrincipal := HashMap.fromIter<Principal, T.UUIDBuffer>(
      Iter.map<(Principal, [T.UUID]), (Principal, T.UUIDBuffer)>(
        Iter.fromArray(loansByPrincipalStable),
        func(entry : (Principal, [T.UUID])) {
          let (principal, uuids) = entry;
          return (principal, Buffer.fromArray(uuids));
        },
      ),
      loanByUUIDStable.size(),
      Principal.equal,
      Principal.hash,
    );
  };
};
