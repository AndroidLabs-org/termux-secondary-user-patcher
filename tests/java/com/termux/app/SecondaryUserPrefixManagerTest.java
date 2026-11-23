package com.termux.app;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import android.app.Application;
import android.content.Context;
import android.content.ContextWrapper;
import android.os.UserManager;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowProcess;
import org.robolectric.shadows.ShadowUserManager;

import java.io.File;

/**
 * Tests for the secondary-user support. These files live outside the patch series on purpose:
 * CI copies them into a scratch tree, they are never part of the shipped APK or of patches/.
 *
 * They pin what the code does today; they do not change it.
 */
@RunWith(RobolectricTestRunner.class)
@Config(application = Application.class, sdk = 28)
public class SecondaryUserPrefixManagerTest {

    private static final int USER = 10;
    private static final int UID = 1010193;
    private static final int PID = 4242;

    // ---- the root script text -------------------------------------------------------------

    @Test
    public void rootScriptCarriesOnlyTheThreeIntegers() {
        String script = SecondaryUserPrefixManager.buildRootScript(USER, UID, PID);
        assertTrue(script.startsWith("PATH=/system/bin:/system/xbin\n"));
        assertTrue(script.contains("\nUSER_ID=10\n"));
        assertTrue(script.contains("\nAPP_UID=1010193\n"));
        assertTrue(script.contains("\nAPP_PID=4242\n"));
        // Nothing else may vary: the same script text for the same ids, every time.
        assertEquals(script, SecondaryUserPrefixManager.buildRootScript(USER, UID, PID));
    }

    @Test
    public void rootScriptRejectsIdentitiesThatDoNotBelongTogether() {
        int[][] bad = {
            {0, 10193, PID},         // primary user: no mapping is ever built
            {-1, UID, PID},          // negative user
            {USER, 0, PID},          // no uid
            {USER, UID, 0},          // no pid
            {USER, UID, -5},         // negative pid
            {USER, 2010193, PID},    // uid belongs to user 20, not user 10
            {11, UID, PID},          // uid belongs to user 10, not user 11
        };
        for (int[] b : bad) {
            try {
                SecondaryUserPrefixManager.buildRootScript(b[0], b[1], b[2]);
                fail("accepted " + b[0] + "/" + b[1] + "/" + b[2]);
            } catch (IllegalArgumentException expected) {
                // refused before any root process is started
            }
        }
    }

    @Test
    public void rootScriptBindsTheUsersDirectoryOntoDataData() {
        // Documents today's scope (the whole /data/user/<N>); narrowing it is a separate decision.
        String script = SecondaryUserPrefixManager.buildRootScript(USER, UID, PID);
        assertTrue(script.contains("SOURCE_ROOT=/data/user/$USER_ID\n"));
        assertTrue(script.contains("TARGET_ROOT=/data/data\n"));
        assertTrue(script.contains("/system/bin/mount -o bind \"$SOURCE_ROOT\" \"$TARGET_ROOT\""));
    }

    @Test
    public void rootScriptNeverEvaluatesStrings() {
        String script = SecondaryUserPrefixManager.buildRootScript(USER, UID, PID);
        assertFalse(script.contains("eval "));
        assertFalse(script.contains("`"));
        assertFalse(script.contains("$(("));
    }

    // ---- inspect(): what Termux decides at startup ----------------------------------------

    private static Context context() {
        return RuntimeEnvironment.application;
    }

    @Test
    public void primaryUserNeedsNoMappingAndNeverCallsRoot() {
        ShadowProcess.setUid(10193); // user 0
        SecondaryUserPrefixManager.Inspection in = SecondaryUserPrefixManager.inspect(context());
        assertFalse(in.secondaryUser);
        assertTrue(in.ready);
        assertEquals(0, in.userId);
        assertTrue(in.diagnostics.contains("Mapping: bypassed"));
        // setup() in user 0 returns at once with success and never starts a process.
        SecondaryUserPrefixManager.SetupResult r = SecondaryUserPrefixManager.setup(context());
        assertTrue(r.success);
    }

    @Test
    public void secondaryUserIsNotReadyUntilMapped() {
        ShadowProcess.setUid(UID);
        SecondaryUserPrefixManager.Inspection in = SecondaryUserPrefixManager.inspect(context());
        assertTrue(in.secondaryUser);
        assertFalse(in.ready);
        assertEquals(USER, in.userId);
        assertTrue(in.diagnostics.contains("Android user: 10"));
        assertTrue(in.diagnostics.contains("Process UID: 1010193"));
        assertFalse(SecondaryUserPrefixManager.isReadyForTermux(context()));
    }

    @Test
    public void readinessFollowsInspectInBothCases() {
        ShadowProcess.setUid(10193);
        assertEquals(SecondaryUserPrefixManager.inspect(context()).ready,
            SecondaryUserPrefixManager.isReadyForTermux(context()));
        ShadowProcess.setUid(UID);
        assertEquals(SecondaryUserPrefixManager.inspect(context()).ready,
            SecondaryUserPrefixManager.isReadyForTermux(context()));
    }

    // ---- the other branches of inspect() and setup() that need no root ---------------------

    private static Context withPackage(final String packageName) {
        return new ContextWrapper(context()) {
            @Override public String getPackageName() { return packageName; }
        };
    }

    private static Context withFilesDir(final File filesDir) {
        return new ContextWrapper(context()) {
            @Override public File getFilesDir() { return filesDir; }
        };
    }

    @Test
    public void aForeignPackageIsRefusedInASecondaryUser() {
        ShadowProcess.setUid(UID);
        SecondaryUserPrefixManager.Inspection in = SecondaryUserPrefixManager.inspect(withPackage("com.example.other"));
        assertTrue(in.secondaryUser);
        assertFalse(in.ready);
        assertEquals("Unexpected application package", in.summary);
        SecondaryUserPrefixManager.SetupResult r = SecondaryUserPrefixManager.setup(withPackage("com.example.other"));
        assertFalse(r.success);
        assertEquals("Unexpected application package", r.summary);
    }

    @Test
    public void aForeignPackageIsNeverReadyInThePrimaryUserEither() {
        ShadowProcess.setUid(10193);
        SecondaryUserPrefixManager.Inspection in = SecondaryUserPrefixManager.inspect(withPackage("com.example.other"));
        assertFalse(in.secondaryUser);
        assertFalse(in.ready);
    }

    @Test
    public void aLockedSecondaryUserMustBeUnlockedFirst() {
        ShadowProcess.setUid(UID);
        UserManager um = (UserManager) context().getSystemService(Context.USER_SERVICE);
        ShadowUserManager shadow = Shadows.shadowOf(um);
        shadow.setUserUnlocked(false);
        SecondaryUserPrefixManager.Inspection in = SecondaryUserPrefixManager.inspect(context());
        assertFalse(in.ready);
        assertEquals("The secondary user must be unlocked", in.summary);
        assertTrue(in.diagnostics.contains("User unlocked: false"));
    }

    @Test
    public void aMissingFilesDirectoryIsReportedNotCrashed() {
        ShadowProcess.setUid(UID);
        SecondaryUserPrefixManager.Inspection in = SecondaryUserPrefixManager.inspect(withFilesDir(null));
        assertFalse(in.ready);
        assertEquals("Android did not provide the app files directory", in.summary);
    }

    @Test
    public void anUnexpectedDataPathMakesNoMountAttempt() {
        ShadowProcess.setUid(UID);
        SecondaryUserPrefixManager.Inspection in = SecondaryUserPrefixManager.inspect(context());
        assertEquals("Unsupported app-data path", in.summary);
        assertTrue(in.diagnostics.contains("No mount was attempted."));
        // setup() stops at the same place and never starts a root process.
        SecondaryUserPrefixManager.SetupResult r = SecondaryUserPrefixManager.setup(context());
        assertFalse(r.success);
        assertEquals("Unsupported app-data path", r.summary);
    }

    // Not unit-tested on purpose: the branches that call Os.stat on /data/user/<N>/... depend on the
    // real filesystem and on how Robolectric treats Os.stat. They are covered on an emulator.

    // ---- the adaptation made when porting to v0.118.3 --------------------------------------

    @Test
    public void completeSecondaryUserPrefixSetupHasNothingToDeferInThisBase() {
        // v0.118.3 has no path-dependent init to postpone, so the hook returns null (no error).
        assertNull(TermuxApplication.completeSecondaryUserPrefixSetup(context()));
    }
}
