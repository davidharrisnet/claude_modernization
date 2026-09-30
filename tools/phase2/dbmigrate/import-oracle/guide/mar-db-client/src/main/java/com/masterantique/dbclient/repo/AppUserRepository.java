package com.masterantique.dbclient.repo;

import com.masterantique.dbclient.model.AppUser;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AppUserRepository extends JpaRepository<AppUser, Integer> {

    /**
     * Sign-in lookup. Usernames are unique ignoring case among active users, enforced by the function-based index
     * ix_users_name_active ON users (CASE WHEN deleted_at IS NULL THEN LOWER(name) END). Oracle uses that index only
     * when the query repeats its expression, so the condition below is written exactly that way; it matches
     * active users only, because the expression is NULL for soft-deleted ones.
     */
    @Query("select u from AppUser u where (case when u.deletedAt is null then lower(u.name) end) = lower(:name)")
    Optional<AppUser> findActiveByName(@Param("name") String name);

    long countByDiscriminator(String discriminator);

    long countByMustResetPasswordTrue();
}
