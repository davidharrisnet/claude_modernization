package com.masterantique.dbclient.repo;

import com.masterantique.dbclient.model.AppUser;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AppUserRepository extends JpaRepository<AppUser, Integer> {

    /**
     * Sign-in lookup. Usernames are unique ignoring case among active users, enforced by the index
     * ix_users_name_active ON users (lower(name)) WHERE deleted_at IS NULL. Lowering both sides lets
     * PostgreSQL use that index.
     */
    @Query("select u from AppUser u where lower(u.name) = lower(:name) and u.deletedAt is null")
    Optional<AppUser> findActiveByName(@Param("name") String name);

    long countByDiscriminator(String discriminator);

    long countByMustResetPasswordTrue();
}
