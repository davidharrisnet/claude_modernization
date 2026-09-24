package com.masterantique.dbclient.model;

/** tickets.state holds the position of these values: 0, 1, 2 (the legacy workflow). Keep the order. */
public enum TicketState {
    SUBMITTED,   // 0
    INPROGRESS,  // 1
    COMPLETED    // 2
}
