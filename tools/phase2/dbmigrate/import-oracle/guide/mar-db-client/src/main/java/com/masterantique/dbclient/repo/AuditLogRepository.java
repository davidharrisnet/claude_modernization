package com.masterantique.dbclient.repo;

import com.masterantique.dbclient.model.AuditLog;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AuditLogRepository extends JpaRepository<AuditLog, Integer> {
}
