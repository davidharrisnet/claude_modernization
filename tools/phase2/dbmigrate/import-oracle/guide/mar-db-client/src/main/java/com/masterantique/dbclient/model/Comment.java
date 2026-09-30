package com.masterantique.dbclient.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "comments")
public class Comment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private AppUser author;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false)
    private Ticket ticket;

    @Column(name = "text", length = 2000)
    private String text;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    protected Comment() {
    }

    public Integer getId() { return id; }
    public AppUser getAuthor() { return author; }
    public Ticket getTicket() { return ticket; }
    public String getText() { return text; }
    public LocalDateTime getCreatedAt() { return createdAt; }
}
