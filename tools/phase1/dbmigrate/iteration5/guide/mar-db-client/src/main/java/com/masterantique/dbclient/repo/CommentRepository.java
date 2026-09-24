package com.masterantique.dbclient.repo;

import com.masterantique.dbclient.model.Comment;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CommentRepository extends JpaRepository<Comment, Integer> {
}
