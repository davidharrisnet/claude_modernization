package com.masterantique.dbclient.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "tickets")
public class Ticket {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @Enumerated(EnumType.ORDINAL)                          // NUMBER(10) 0/1/2
    @Column(name = "state", nullable = false)
    private TicketState state;

    @Column(name = "description", length = 2000)
    private String description;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")                          // assigned employee; NULL while SUBMITTED
    private AppUser assignee;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "customer_id")
    private AppUser customer;

    @Column(name = "submitted_date")
    private LocalDateTime submittedDate;

    @Column(name = "assigned_date")
    private LocalDateTime assignedDate;

    @Column(name = "completed_date")
    private LocalDateTime completedDate;

    protected Ticket() {
    }

    public Integer getId() { return id; }
    public TicketState getState() { return state; }
    public String getDescription() { return description; }
    public AppUser getAssignee() { return assignee; }
    public AppUser getCustomer() { return customer; }
    public LocalDateTime getSubmittedDate() { return submittedDate; }
    public LocalDateTime getAssignedDate() { return assignedDate; }
    public LocalDateTime getCompletedDate() { return completedDate; }
}
