package com.masterantique.dbclient.repo;

import com.masterantique.dbclient.model.Ticket;
import com.masterantique.dbclient.model.TicketState;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TicketRepository extends JpaRepository<Ticket, Integer> {

    long countByState(TicketState state);
}
