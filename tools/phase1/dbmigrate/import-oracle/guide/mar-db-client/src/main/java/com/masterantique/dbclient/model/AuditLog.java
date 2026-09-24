package com.masterantique.dbclient.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/** Workflow audit trail: ids and timestamps only, never comment text or descriptions. */
@Entity
@Table(name = "audit_logs")
public class AuditLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @Column(name = "timestamp", nullable = false)
    private LocalDateTime timestamp;

    @Column(name = "user_id", nullable = false)
    private Integer userId;

    @Column(name = "action", nullable = false)
    private Integer action;          // numeric code from the legacy application

    @Column(name = "entity_type", nullable = false)
    private Integer entityType;

    @Column(name = "entity_id", nullable = false)
    private Integer entityId;

    protected AuditLog() {
    }

    public Integer getId() { return id; }
    public LocalDateTime getTimestamp() { return timestamp; }
    public Integer getUserId() { return userId; }
    public Integer getAction() { return action; }
    public Integer getEntityType() { return entityType; }
    public Integer getEntityId() { return entityId; }
}
